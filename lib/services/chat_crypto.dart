import 'dart:convert';
import 'dart:typed_data';

import 'package:quark/models/account_keys.dart';
import 'package:quark/models/chat_keys.dart';
import 'package:quark/services/account_crypto.dart';
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
/// - Poll answers (#3894): the same over [padPollAnswer], bound to
///   [pollAnswerAad].
class ChatCrypto {
  /// Wraps an initialized libsodium.
  ChatCrypto(this.sodium) : account = AccountCrypto(sodium);

  /// The libsodium instance everything here runs on.
  final SodiumSumo sodium;

  /// The account key derivation and wrapping chat's identity wraps run on,
  /// shared with the vault (#3457).
  final AccountCrypto account;

  /// Loads libsodium once for the life of the app ([AccountCrypto.load]).
  static Future<ChatCrypto> load() async =>
      ChatCrypto((await AccountCrypto.load()).sodium);

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

  /// [AccountCrypto.deriveAuthKeys]: the Quark's `authKey` and the chat
  /// identity's password wrap key. The caller disposes the result.
  AuthKeys deriveAuthKeys(String password, Uint8List salt, KdfParams params) =>
      account.deriveAuthKeys(password, salt, params);

  /// [AccountCrypto.deriveRecoveryKeys]: the Quark's `recoveryKey` and the
  /// chat identity's phrase wrap key. The caller disposes the result.
  AuthKeys deriveRecoveryKeys(
    String phrase,
    Uint8List salt,
    KdfParams params,
  ) => account.deriveRecoveryKeys(phrase, salt, params);

  /// A new recovery phrase: [recoveryPhraseWords] words of [recoveryWords]
  /// joined by hyphens, the Quark's own format. The list has 256 words, so
  /// each random byte picks one with no bias: 16 words, 128 bits (#2783).
  String generateRecoveryPhrase() => [
    for (final byte in sodium.randombytes.buf(recoveryPhraseWords))
      recoveryWords[byte],
  ].join('-');

  /// Encrypts [identity]'s seeds under Argon2id([secret], a fresh salt)
  /// ([AccountCrypto.wrap]).
  WrappedSecret wrap(ChatIdentity identity, String secret, KdfParams params) =>
      account.wrap(identity.seeds, secret, params);

  /// Encrypts [identity]'s seeds directly under [key]
  /// ([AccountCrypto.wrapWithKey]). The caller disposes [key].
  WrappedSecret wrapWithKey(
    ChatIdentity identity,
    SecureKey key,
    Uint8List salt,
  ) => account.wrapWithKey(identity.seeds, key, salt);

  /// Opens what [wrap] produced.
  ///
  /// A wrong [secret] throws a [MessageException] carrying [wrongSecret], so
  /// [Errors.message] shows it as written.
  ChatIdentity unwrap(
    WrappedSecret wrapped,
    String secret,
    KdfParams params, {
    String wrongSecret = Errors.chatKeysWrongPassword,
  }) => identityFromSeeds(
    account.unwrap(wrapped, secret, params, wrongSecret: wrongSecret),
  );

  /// Opens what [wrapWithKey] produced. A wrong [key] throws a
  /// [MessageException] carrying [wrongSecret]. The caller disposes [key].
  ChatIdentity unwrapWithKey(
    WrappedSecret wrapped,
    SecureKey key, {
    String wrongSecret = Errors.chatKeysWrongPassword,
  }) => identityFromSeeds(
    account.unwrapWithKey(wrapped, key, wrongSecret: wrongSecret),
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

  /// The additional data a poll answer's ciphertext is bound to (#3894):
  ///
  /// `"quark-chat-poll-answer-v1" 0x00 || be64(channelId) || be64(keyVersion)
  /// || be64(messageId) [|| be64(userId)]`
  ///
  /// So the Quark can't move an answer to another poll or channel. [userId]
  /// is the account that answered, and is left out on an anonymous poll,
  /// whose readers don't know whose answer they are opening; on any other
  /// poll it stops the Quark pinning an answer on another account.
  Uint8List pollAnswerAad({
    required int channelId,
    required int keyVersion,
    required int messageId,
    int? userId,
  }) => Uint8List.fromList([
    ...utf8.encode('quark-chat-poll-answer-v1'),
    0,
    ..._be64(channelId),
    ..._be64(keyVersion),
    ..._be64(messageId),
    if (userId != null) ..._be64(userId),
  ]);

  /// How long every poll answer's plaintext is, so its ciphertext is the
  /// 4136 bytes the Quark insists on and says nothing of what was chosen.
  static const pollAnswerPlaintextBytes = 4 << 10;

  /// [json], an answer's plaintext, in UTF-8 zero-padded to
  /// [pollAnswerPlaintextBytes]. Throws a [MessageException] for one that
  /// doesn't fit.
  static Uint8List padPollAnswer(String json) {
    final bytes = utf8.encode(json);
    if (bytes.length > pollAnswerPlaintextBytes) {
      throw const MessageException(Errors.chatPollAnswerTooLong);
    }
    return Uint8List(pollAnswerPlaintextBytes)..setAll(0, bytes);
  }

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

  /// What [padReaction] or [padPollAnswer] padded, with the zeros dropped.
  static String stripPadding(Uint8List padded) {
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
