import 'dart:convert';
import 'dart:typed_data';

import 'package:quark/models/chat_keys.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/recovery_phrase.dart';
import 'package:sodium/sodium_sumo.dart';

/// Every cryptographic operation chat needs, on libsodium (#2416).
///
/// Native builds link libsodium through the `sodium` package's build hook; web
/// loads `web/sodium.js`, the sumo build, because Argon2id (`crypto_pwhash`) is
/// sumo-only there. The Quark never runs any of this: it stores what [wrap]
/// produces and hands it back.
///
/// - Identity: [generateIdentity], [wrap] and [unwrap], and for the split
///   wraps [deriveAuthKeys], [deriveRecoveryKeys], [wrapWithKey] and
///   [unwrapWithKey] (#2430). [generateRecoveryPhrase] makes the phrase.
/// - Key grants (#2417): [seal] and [openSealed] for `crypto_box_seal` to a
///   member's X25519 key, and [sign] and [verify] for Ed25519.
/// - Messages (#2418): [newChannelKey], [channelKeyFromBytes], [encrypt] and
///   [decrypt], XChaCha20-Poly1305 with a random nonce, bound to
///   [messageAad].
/// - Reactions (#2426): the same [encrypt] and [decrypt] over [padReaction],
///   bound to [reactionAad].
class ChatCrypto {
  /// Wraps an initialized libsodium.
  ChatCrypto(this.sodium);

  /// The libsodium instance everything here runs on.
  final SodiumSumo sodium;

  static Future<ChatCrypto>? _loading;

  /// Loads libsodium once for the life of the app.
  ///
  /// On web this waits for `sodium.js`, which `web/index.html` loads.
  static Future<ChatCrypto> load() =>
      _loading ??= Future(() async => ChatCrypto(await SodiumSumoInit.init()))
          .catchError((Object e) {
            _loading = null;
            throw e;
          });

  Aead get _aead => sodium.crypto.aeadXChaCha20Poly1305IETF;

  /// A new identity from fresh random seeds.
  ChatIdentity generateIdentity() => _identityFromSeeds(
    sodium.secureRandom(sodium.crypto.box.seedBytes),
    sodium.secureRandom(sodium.crypto.sign.seedBytes),
  );

  /// Rebuilds an identity from [ChatIdentity.seeds], the form the native cache
  /// keeps.
  ChatIdentity identityFromSeeds(Uint8List seeds) {
    final boxSeedBytes = sodium.crypto.box.seedBytes;
    if (seeds.length != boxSeedBytes + sodium.crypto.sign.seedBytes) {
      throw const FormatException('chat identity seeds have the wrong length');
    }
    return _identityFromSeeds(
      sodium.secureCopy(Uint8List.sublistView(seeds, 0, boxSeedBytes)),
      sodium.secureCopy(Uint8List.sublistView(seeds, boxSeedBytes)),
    );
  }

  ChatIdentity _identityFromSeeds(SecureKey boxSeed, SecureKey signSeed) {
    try {
      return ChatIdentity(
        box: sodium.crypto.box.seedKeyPair(boxSeed),
        sign: sodium.crypto.sign.seedKeyPair(signSeed),
        seeds: Uint8List.fromList([
          ...boxSeed.extractBytes(),
          ...signSeed.extractBytes(),
        ]),
      );
    } finally {
      boxSeed.dispose();
      signSeed.dispose();
    }
  }

  /// Derives the two keys a password stands for (#2430), so the Quark is sent
  /// one and can open nothing with it.
  ///
  /// The construction is permanent once accounts exist:
  ///
  /// ```text
  /// master  = Argon2id13(password, salt, params.opsLimit, params.memLimit), 32 bytes
  /// authKey = HKDF-SHA256(ikm = master, salt = none, info = "auth"), 32 bytes
  /// wrapKey = HKDF-SHA256(ikm = master, salt = none, info = "chat-wrap"), 32 bytes
  /// ```
  ///
  /// HKDF is RFC 5869 extract-then-expand, with the empty salt the RFC reads
  /// as 32 zero bytes. [salt] is the account's 16-byte auth salt from
  /// `GET /auth/salt`. The caller disposes the result.
  AuthKeys deriveAuthKeys(String password, Uint8List salt, KdfParams params) =>
      _deriveSplit(password, salt, params, 'auth', 'chat-wrap');

  /// The same construction over a recovery phrase (#2430): `authKey` is the
  /// `recoveryKey` the Quark is sent in the phrase's place, and `wrapKey`
  /// opens the chat identity's phrase wrap.
  ///
  /// ```text
  /// phraseMaster = Argon2id13(normalize(phrase), salt, params), 32 bytes
  /// recoveryKey  = HKDF-SHA256(phraseMaster, info = "recovery-auth"), 32 bytes
  /// wrapKey      = HKDF-SHA256(phraseMaster, info = "recovery-wrap"), 32 bytes
  /// ```
  ///
  /// [phrase] is normalized here ([normalizeRecoveryPhrase]), so a phrase
  /// typed with capitals derives the same keys. [salt] is the account's auth
  /// salt. The caller disposes the result.
  AuthKeys deriveRecoveryKeys(
    String phrase,
    Uint8List salt,
    KdfParams params,
  ) => _deriveSplit(
    normalizeRecoveryPhrase(phrase),
    salt,
    params,
    'recovery-auth',
    'recovery-wrap',
  );

  /// A new recovery phrase: [recoveryPhraseWords] words of [recoveryWords]
  /// joined by hyphens, the Quark's own format. The list has 256 words, so
  /// each random byte picks one with no bias.
  String generateRecoveryPhrase() => [
    for (final byte in sodium.randombytes.buf(recoveryPhraseWords))
      recoveryWords[byte],
  ].join('-');

  /// One Argon2id run over [secret], split by HKDF-SHA256 into a key sent
  /// under [authInfo] and a wrap key under [wrapInfo].
  AuthKeys _deriveSplit(
    String secret,
    Uint8List salt,
    KdfParams params,
    String authInfo,
    String wrapInfo,
  ) {
    final hkdf = sodium.crypto.kdfHkdfSha256;
    final master = _derive(secret, salt, params);
    try {
      final prk = master.runUnlockedSync((ikm) => hkdf.extract(ikm: ikm));
      try {
        final authKey = hkdf.expand(
          masterKey: prk,
          context: authInfo,
          outLen: 32,
        );
        try {
          return AuthKeys(
            authKey: base64Encode(authKey.extractBytes()),
            wrapKey: hkdf.expand(
              masterKey: prk,
              context: wrapInfo,
              outLen: _aead.keyBytes,
            ),
          );
        } finally {
          authKey.dispose();
        }
      } finally {
        prk.dispose();
      }
    } finally {
      master.dispose();
    }
  }

  /// Encrypts [identity]'s seeds under Argon2id([secret], a fresh salt).
  ///
  /// The result is `nonce || XChaCha20-Poly1305(seeds)`. [secret] is the
  /// recovery phrase, which the caller normalizes first, or the login password
  /// of an account still on the first scheme ([KdfParams.algorithm]).
  WrappedSecret wrap(ChatIdentity identity, String secret, KdfParams params) {
    final salt = sodium.randombytes.buf(sodium.crypto.pwhash.saltBytes);
    final key = _derive(secret, salt, params);
    try {
      return wrapWithKey(identity, key, salt);
    } finally {
      key.dispose();
    }
  }

  /// Encrypts [identity]'s seeds directly under [key], with no Argon2id of its
  /// own: `nonce || XChaCha20-Poly1305(seeds)`. [salt] is recorded beside the
  /// wrap, for whoever re-derives [key]. The caller disposes [key].
  WrappedSecret wrapWithKey(
    ChatIdentity identity,
    SecureKey key,
    Uint8List salt,
  ) {
    final nonce = sodium.randombytes.buf(_aead.nonceBytes);
    final cipherText = _aead.encrypt(
      message: identity.seeds,
      nonce: nonce,
      key: key,
    );
    return WrappedSecret(
      wrapped: Uint8List.fromList([...nonce, ...cipherText]),
      salt: salt,
    );
  }

  /// Opens what [wrap] produced.
  ///
  /// A wrong [secret] throws a [MessageException] carrying [wrongSecret], so
  /// [Errors.message] shows it as written.
  ChatIdentity unwrap(
    WrappedSecret wrapped,
    String secret,
    KdfParams params, {
    String wrongSecret = Errors.chatKeysWrongPassword,
  }) {
    final key = _derive(secret, wrapped.salt, params);
    try {
      return unwrapWithKey(wrapped, key, wrongSecret: wrongSecret);
    } finally {
      key.dispose();
    }
  }

  /// Opens what [wrapWithKey] produced. A wrong [key] throws a
  /// [MessageException] carrying [wrongSecret]. The caller disposes [key].
  ChatIdentity unwrapWithKey(
    WrappedSecret wrapped,
    SecureKey key, {
    String wrongSecret = Errors.chatKeysWrongPassword,
  }) {
    final nonceBytes = _aead.nonceBytes;
    if (wrapped.wrapped.length <= nonceBytes) {
      throw MessageException(wrongSecret);
    }
    final Uint8List seeds;
    try {
      seeds = _aead.decrypt(
        cipherText: Uint8List.sublistView(wrapped.wrapped, nonceBytes),
        nonce: Uint8List.sublistView(wrapped.wrapped, 0, nonceBytes),
        key: key,
      );
    } on SodiumException {
      throw MessageException(wrongSecret);
    }
    return identityFromSeeds(seeds);
  }

  SecureKey _derive(String secret, Uint8List salt, KdfParams params) =>
      sodium.crypto.pwhash.callStr(
        outLen: _aead.keyBytes,
        password: secret,
        salt: salt,
        opsLimit: params.opsLimit,
        memLimit: params.memLimit,
        alg: CryptoPwhashAlgorithm.argon2id13,
      );

  /// `crypto_box_seal`: [message] readable only by the holder of
  /// [boxPublicKey]'s secret half. Used for key grants (#2417).
  Uint8List seal(Uint8List message, Uint8List boxPublicKey) =>
      sodium.crypto.box.seal(message: message, publicKey: boxPublicKey);

  /// Opens a [seal]ed box addressed to [identity]. Throws [SodiumException]
  /// when it was sealed to anyone else or tampered with.
  Uint8List openSealed(Uint8List sealed, ChatIdentity identity) =>
      sodium.crypto.box.sealOpen(
        cipherText: sealed,
        publicKey: identity.box.publicKey,
        secretKey: identity.box.secretKey,
      );

  /// A detached Ed25519 signature over [message] by [identity].
  Uint8List sign(Uint8List message, ChatIdentity identity) => sodium.crypto.sign
      .detached(message: message, secretKey: identity.sign.secretKey);

  /// Whether [signature] is [signPublicKey]'s signature over [message].
  bool verify(Uint8List message, Uint8List signature, Uint8List signPublicKey) {
    if (signature.length != sodium.crypto.sign.bytes ||
        signPublicKey.length != sodium.crypto.sign.publicKeyBytes) {
      return false;
    }
    return sodium.crypto.sign.verifyDetached(
      message: message,
      signature: signature,
      publicKey: signPublicKey,
    );
  }

  /// The bytes a key grant's signature covers (#2417):
  ///
  /// `"quark-chat-grant-v1" 0x00 || be64(channelId) || be64(version) ||
  /// be64(userId) || BLAKE2b-256(sealedKey)`
  ///
  /// Binding the recipient and version means a grant can't be replayed to
  /// someone else or as another version.
  Uint8List grantMessage({
    required int channelId,
    required int version,
    required int userId,
    required Uint8List sealedKey,
  }) => Uint8List.fromList([
    ...utf8.encode('quark-chat-grant-v1'),
    0,
    ..._be64(channelId),
    ..._be64(version),
    ..._be64(userId),
    ...sodium.crypto.genericHash(message: sealedKey, outLen: 32),
  ]);

  /// The bytes a channel event's signature covers (#2417):
  ///
  /// `"quark-chat-event-v1" 0x00 || be64(channelId) || be64(eventId) ||
  /// be64(actorId) || kind 0x00 || payload`, the payload exactly as the Quark
  /// stored it.
  Uint8List eventMessage({
    required int channelId,
    required int eventId,
    required int actorId,
    required String kind,
    required String payload,
  }) => Uint8List.fromList([
    ...utf8.encode('quark-chat-event-v1'),
    0,
    ..._be64(channelId),
    ..._be64(eventId),
    ..._be64(actorId),
    ...utf8.encode(kind),
    0,
    ...utf8.encode(payload),
  ]);

  /// The additional data a message's ciphertext is bound to (#2418):
  ///
  /// `"quark-chat-msg-v1" 0x00 || be64(channelId) || be64(keyVersion)`
  ///
  /// Pass it to both [encrypt] and [decrypt], so the Quark can't move a
  /// message to another channel or relabel its key version without it failing
  /// to open.
  Uint8List messageAad({required int channelId, required int keyVersion}) =>
      Uint8List.fromList([
        ...utf8.encode('quark-chat-msg-v1'),
        0,
        ..._be64(channelId),
        ..._be64(keyVersion),
      ]);

  /// The additional data a reaction's ciphertext is bound to (#2426):
  ///
  /// `"quark-chat-reaction-v1" 0x00 || be64(channelId) || be64(keyVersion) ||
  /// be64(messageId) || be64(userId)`
  ///
  /// So the Quark can't move a reaction to another message or pin it on
  /// another account. Reactions go with the account that made them, so the
  /// user id is never cleared the way a deleted author's is.
  Uint8List reactionAad({
    required int channelId,
    required int keyVersion,
    required int messageId,
    required int userId,
  }) => Uint8List.fromList([
    ...utf8.encode('quark-chat-reaction-v1'),
    0,
    ..._be64(channelId),
    ..._be64(keyVersion),
    ..._be64(messageId),
    ..._be64(userId),
  ]);

  /// How long every reaction's plaintext is, so the ciphertext's length
  /// doesn't tell the Quark which emoji it is.
  static const reactionPlaintextBytes = 64;

  /// [emoji] in UTF-8, zero-padded to [reactionPlaintextBytes]. Throws a
  /// [FormatException] for one that doesn't fit, or is empty.
  static Uint8List padReaction(String emoji) {
    final bytes = utf8.encode(emoji);
    if (bytes.isEmpty || bytes.length > reactionPlaintextBytes) {
      throw const FormatException('a reaction must be 1 to 64 bytes');
    }
    return Uint8List(reactionPlaintextBytes)..setAll(0, bytes);
  }

  /// The emoji [padReaction] padded, with the zeros dropped.
  static String stripReaction(Uint8List padded) {
    final end = padded.indexOf(0);
    return utf8.decode(
      end < 0 ? padded : Uint8List.sublistView(padded, 0, end),
    );
  }

  /// Big-endian 64 bits without `ByteData.setInt64`, which the web lacks. Ids
  /// are positive and below 2^53.
  static List<int> _be64(int value) {
    final high = value ~/ 0x100000000;
    final low = value % 0x100000000;
    return [
      for (final part in [high, low])
        for (var shift = 24; shift >= 0; shift -= 8) (part >> shift) & 0xff,
    ];
  }

  /// A new random channel key for [encrypt]. The caller disposes it.
  SecureKey newChannelKey() => _aead.keygen();

  /// A channel key from the bytes a key grant carried. The caller disposes it.
  SecureKey channelKeyFromBytes(Uint8List bytes) {
    if (bytes.length != _aead.keyBytes) {
      throw const FormatException('a channel key has the wrong length');
    }
    return sodium.secureCopy(bytes);
  }

  /// XChaCha20-Poly1305 under [key] with a random nonce: returns
  /// `nonce || ciphertext`. [additionalData] is authenticated, not encrypted.
  Uint8List encrypt(
    Uint8List message,
    SecureKey key, {
    Uint8List? additionalData,
  }) {
    final nonce = sodium.randombytes.buf(_aead.nonceBytes);
    return Uint8List.fromList([
      ...nonce,
      ..._aead.encrypt(
        message: message,
        nonce: nonce,
        key: key,
        additionalData: additionalData,
      ),
    ]);
  }

  /// Opens what [encrypt] produced. Throws [SodiumException] for a wrong key,
  /// wrong [additionalData] or tampered bytes.
  Uint8List decrypt(
    Uint8List sealed,
    SecureKey key, {
    Uint8List? additionalData,
  }) {
    final nonceBytes = _aead.nonceBytes;
    if (sealed.length < nonceBytes + _aead.aBytes) {
      throw const FormatException('ciphertext is too short');
    }
    return _aead.decrypt(
      cipherText: Uint8List.sublistView(sealed, nonceBytes),
      nonce: Uint8List.sublistView(sealed, 0, nonceBytes),
      key: key,
      additionalData: additionalData,
    );
  }
}

/// A user's unlocked chat identity: an X25519 keypair for sealed boxes and an
/// Ed25519 keypair for signatures (#2416).
///
/// Holds secret keys. [dispose] it when the identity is locked.
class ChatIdentity {
  /// Builds an identity from its keypairs and the seeds they came from.
  ChatIdentity({required this.box, required this.sign, required this.seeds});

  /// X25519: what key grants are sealed to.
  final KeyPair box;

  /// Ed25519: what key grants and system events are signed with.
  final KeyPair sign;

  /// The box seed followed by the sign seed, 64 bytes: what [ChatCrypto.wrap]
  /// encrypts and the native cache stores.
  final Uint8List seeds;

  /// The public halves, as the Quark publishes them.
  ChatPublicKeys get publicKeys => ChatPublicKeys(
    boxPublicKey: box.publicKey,
    signPublicKey: sign.publicKey,
  );

  /// Frees the secret keys and zeroes the seeds.
  void dispose() {
    box.dispose();
    sign.dispose();
    seeds.fillRange(0, seeds.length, 0);
  }
}

/// What [ChatCrypto.deriveAuthKeys] makes of a password, or
/// [ChatCrypto.deriveRecoveryKeys] of a recovery phrase (#2430): the key the
/// Quark is sent in the secret's place, and the key that wraps the chat
/// identity and never leaves the client.
///
/// Neither is to be logged or kept past the request it was derived for.
/// [dispose] it once both have been used.
class AuthKeys {
  /// Pairs the two keys.
  AuthKeys({required this.authKey, required this.wrapKey});

  /// The standard padded base64 of 32 bytes: `authKey`, or `recoveryKey`, on
  /// the wire.
  final String authKey;

  /// The XChaCha20-Poly1305 key of the chat identity's password wrap, or its
  /// phrase wrap.
  final SecureKey wrapKey;

  /// Frees the wrap key.
  void dispose() => wrapKey.dispose();
}
