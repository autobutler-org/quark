import 'package:flutter/foundation.dart';

/// Whether the Quark can repair its own installation by restarting (#2121).
@immutable
class RepairStatus {
  /// Creates a status.
  const RepairStatus({required this.available, this.reason = ''});

  /// Reads `GET /api/v0/admin/repair`.
  factory RepairStatus.fromJson(Map<String, dynamic> json) => RepairStatus(
    available: json['available'] as bool? ?? false,
    reason: json['reason'] as String? ?? '',
  );

  /// The Quark is not Linux, so there is nothing to repair this way.
  static const String unsupportedOs = 'unsupported_os';

  /// The Quark is not running as its installed systemd service.
  static const String notService = 'not_service';

  /// The installed unit predates #2120, so a restart would not repair
  /// anything until `sudo quark install` is run once on the device.
  static const String unitOutdated = 'unit_outdated';

  /// Whether a restart will reapply the system setup.
  final bool available;

  /// Why not, as the Quark's code, when [available] is false. Empty otherwise.
  final String reason;
}
