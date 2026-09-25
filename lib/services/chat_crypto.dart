import 'dart:convert';
import 'dart:typed_data';

import 'package:quark/models/chat_keys.dart';
import 'package:quark/utils/error_text.dart';
import 'package:sodium/sodium_sumo.dart';

/// Every cryptographic operation chat needs, on libsodium (#2416).
///
/// Native builds link libsodium through the `sodium` package's build hook; web
/// loads `web/sodium.js`, the sumo build, because Argon2id (`crypto_pwhash`) is
/// sumo-only there. The Quark never runs any of this: it stores what [wrap]
/// produces and hands it back.
///
/// - Identity: [generateIdentity], [wrap] and [unwrap].
/// - Key grants (#2417): [seal] and [openSealed] for `crypto_box_seal` to a
///   member's X25519 key, and [sign] and [verify] for Ed25519.
/// - Messages (#2418): [newChannelKey], [channelKeyFromBytes], [encrypt] and
///   [decrypt], XChaCha20-Poly1305 with a random nonce, bound to
///   [messageAad].
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

  /// Encrypts [identity]'s seeds under Argon2id([secret], a fresh salt).
  ///
  /// The result is `nonce || XChaCha20-Poly1305(seeds)`. [secret] is the login
  /// password or the recovery phrase; the caller normalizes a phrase first.
  WrappedSecret wrap(ChatIdentity identity, String secret, KdfParams params) {
    final salt = sodium.randombytes.buf(sodium.crypto.pwhash.saltBytes);
    final key = _derive(secret, salt, params);
    try {
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
    } finally {
      key.dispose();
    }
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
    } finally {
      key.dispose();
    }
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
