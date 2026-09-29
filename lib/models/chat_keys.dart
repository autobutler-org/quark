import 'dart:convert';
import 'dart:typed_data';

/// The Argon2id cost a wrapped chat key was derived with, stored beside it as
/// `kdfParams` so the cost can rise later without breaking older wraps.
class KdfParams {
  /// Builds explicit parameters. [memLimit] is in bytes.
  const KdfParams({required this.opsLimit, required this.memLimit});

  /// Argon2id passes.
  final int opsLimit;

  /// Argon2id memory, in bytes.
  final int memLimit;

  /// What new wraps use: 3 passes over 64 MiB.
  ///
  /// Measured with the shipped sodium.js (sumo 0.8.4) in Chrome on an Apple
  /// M2 Pro: 100 ms. A mid-range phone's browser is roughly five times slower,
  /// which keeps an unlock under the one-second budget in #2416. 128 MiB took
  /// 220 ms and 256 MiB 456 ms on the same machine.
  static const standard = KdfParams(opsLimit: 3, memLimit: 64 << 20);

  /// The only algorithm written or read.
  static const algorithm = 'argon2id13';

  /// Reads `kdfParams`. Anything but [algorithm] is refused rather than
  /// guessed at.
  factory KdfParams.fromJson(Map<String, dynamic> json) {
    if (json['alg'] != algorithm) {
      throw FormatException('unsupported chat key KDF: ${json['alg']}');
    }
    return KdfParams(
      opsLimit: (json['opsLimit'] as num).toInt(),
      memLimit: (json['memLimit'] as num).toInt(),
    );
  }

  /// The `kdfParams` object.
  Map<String, dynamic> toJson() => {
    'alg': algorithm,
    'opsLimit': opsLimit,
    'memLimit': memLimit,
  };
}

/// One wrap of a chat identity: `nonce || ciphertext` and the Argon2id salt
/// it was derived with.
class WrappedSecret {
  /// Pairs a wrap with its salt.
  const WrappedSecret({required this.wrapped, required this.salt});

  /// `nonce || XChaCha20-Poly1305(seeds)`.
  final Uint8List wrapped;

  /// The Argon2id salt.
  final Uint8List salt;
}

/// A user's published chat keys: what any signed-in user may fetch.
class ChatPublicKeys {
  /// Pairs the two public keys.
  const ChatPublicKeys({
    required this.boxPublicKey,
    required this.signPublicKey,
  });

  /// X25519, what key grants are sealed to.
  final Uint8List boxPublicKey;

  /// Ed25519, what the user's signatures verify against.
  final Uint8List signPublicKey;

  /// Reads `GET /api/v0/chat/keys/:userId`.
  factory ChatPublicKeys.fromJson(Map<String, dynamic> json) => ChatPublicKeys(
    boxPublicKey: base64Decode(json['boxPublicKey'] as String),
    signPublicKey: base64Decode(json['signPublicKey'] as String),
  );
}

/// Everything the Quark stores for one user's chat identity (#2416): the
/// public keys, and the private seeds wrapped under the login password and,
/// when the client had it, the recovery phrase.
class WrappedChatKeys {
  /// Builds the stored form.
  const WrappedChatKeys({
    required this.publicKeys,
    required this.byPassword,
    required this.byPhrase,
    required this.kdfParams,
  });

  /// The public halves.
  final ChatPublicKeys publicKeys;

  /// Wrapped under the login password.
  final WrappedSecret byPassword;

  /// Wrapped under the recovery phrase; null for keys made at a sign-in that
  /// had no phrase to hand, which recovery cannot open.
  final WrappedSecret? byPhrase;

  /// The Argon2id cost both wraps used.
  final KdfParams kdfParams;

  /// Reads `GET /api/v0/chat/keys/me`.
  factory WrappedChatKeys.fromJson(Map<String, dynamic> json) {
    final byPhrase = json['wrappedByPhrase'] as String?;
    final saltRp = json['saltRp'] as String?;
    return WrappedChatKeys(
      publicKeys: ChatPublicKeys.fromJson(json),
      byPassword: WrappedSecret(
        wrapped: base64Decode(json['wrappedByPassword'] as String),
        salt: base64Decode(json['saltPw'] as String),
      ),
      byPhrase: byPhrase == null || saltRp == null
          ? null
          : WrappedSecret(
              wrapped: base64Decode(byPhrase),
              salt: base64Decode(saltRp),
            ),
      kdfParams: KdfParams.fromJson(json['kdfParams'] as Map<String, dynamic>),
    );
  }

  /// The body of `PUT /api/v0/chat/keys/me` and of `chatKeys` in
  /// `POST /api/v0/auth/recover`.
  Map<String, dynamic> toJson() => {
    'boxPublicKey': base64Encode(publicKeys.boxPublicKey),
    'signPublicKey': base64Encode(publicKeys.signPublicKey),
    'wrappedByPassword': base64Encode(byPassword.wrapped),
    'saltPw': base64Encode(byPassword.salt),
    if (byPhrase != null) ...{
      'wrappedByPhrase': base64Encode(byPhrase!.wrapped),
      'saltRp': base64Encode(byPhrase!.salt),
    },
    'kdfParams': kdfParams.toJson(),
  };
}
