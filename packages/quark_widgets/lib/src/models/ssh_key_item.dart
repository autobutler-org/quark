import 'package:flutter/foundation.dart';

/// One public key allowed to sign in over SSH, as `SshAccessPanel` shows it.
@immutable
class SshKeyItem {
  /// Creates a key row's data.
  const SshKeyItem({
    required this.fingerprint,
    required this.type,
    this.comment = '',
  });

  /// The SHA256 fingerprint. Identifies the key in callbacks and keys.
  final String fingerprint;

  /// The key algorithm, such as `ssh-ed25519`.
  final String type;

  /// The text after the key, often `user@host`. Empty hides it.
  final String comment;
}
