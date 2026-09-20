import 'package:flutter/foundation.dart';

/// One public key allowed to sign in to the Quark over SSH.
@immutable
class SshKey {
  /// Creates a key description.
  const SshKey({
    required this.type,
    required this.fingerprint,
    required this.comment,
  });

  /// Reads a key from `GET /api/v0/ssh/status`.
  factory SshKey.fromJson(Map<String, dynamic> json) => SshKey(
    type: json['type'] as String? ?? '',
    fingerprint: json['fingerprint'] as String? ?? '',
    comment: json['comment'] as String? ?? '',
  );

  /// The key algorithm, such as `ssh-ed25519`.
  final String type;

  /// The SHA256 fingerprint, which identifies the key for removal.
  final String fingerprint;

  /// The text after the key, often `user@host`. May be empty.
  final String comment;
}

/// Whether SSH access can be managed on the Quark, whether it is on, and who
/// may sign in (#2131).
@immutable
class SshAccessStatus {
  /// Creates a status.
  const SshAccessStatus({
    required this.available,
    required this.enabled,
    required this.keys,
    this.reason,
  });

  /// Reads `GET /api/v0/ssh/status`.
  factory SshAccessStatus.fromJson(Map<String, dynamic> json) =>
      SshAccessStatus(
        available: json['available'] as bool? ?? false,
        reason: json['reason'] as String?,
        enabled: json['enabled'] as bool? ?? false,
        keys: (json['keys'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SshKey.fromJson)
            .toList(growable: false),
      );

  /// Whether SSH access can be managed here at all.
  final bool available;

  /// Why not, as the Quark's code (`sshd_missing`, ...), when [available] is
  /// false.
  final String? reason;

  /// Whether sshd is running.
  final bool enabled;

  /// The keys allowed to sign in.
  final List<SshKey> keys;
}
