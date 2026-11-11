import 'package:flutter/foundation.dart';

/// Whether the Quark can restart itself from Settings (#4019).
@immutable
class RestartStatus {
  /// Creates a status.
  const RestartStatus({required this.available, this.reason = ''});

  /// Reads `GET /api/v0/admin/restart`.
  factory RestartStatus.fromJson(Map<String, dynamic> json) => RestartStatus(
    available: json['available'] as bool? ?? false,
    reason: json['reason'] as String? ?? '',
  );

  /// Nothing is known to start the Quark again after it exits: it is not the
  /// installed service and `QUARK_RESTART_SUPERVISED` is not set.
  static const String notSupervised = 'not_supervised';

  /// Whether a restart will bring the Quark back.
  final bool available;

  /// Why not, as the Quark's code, when [available] is false. Empty otherwise.
  final String reason;
}
