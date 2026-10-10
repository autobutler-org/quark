import 'package:flutter/foundation.dart';

/// What the Quark is called, and whether it can be renamed (#2344).
@immutable
class HostnameStatus {
  /// Creates a status.
  const HostnameStatus({
    required this.available,
    required this.hostname,
    this.advertisedHostname = '',
    this.reason,
  });

  /// Reads `GET` or `PUT /api/v0/hostname`, or the data of a
  /// `hostname_changed` event, which carries the two names only.
  factory HostnameStatus.fromJson(Map<String, dynamic> json) => HostnameStatus(
    available: json['available'] as bool? ?? false,
    reason: json['reason'] as String?,
    hostname: json['hostname'] as String? ?? '',
    advertisedHostname: json['advertisedHostname'] as String? ?? '',
  );

  /// Whether this Quark can be renamed. False on a Quark that is not the
  /// installed Linux service.
  final bool available;

  /// Why not, when [available] is false: `unsupported_os`, `not_service` or
  /// `helper_missing`.
  final String? reason;

  /// The system hostname.
  final String hostname;

  /// The name the device answers to on the network, without `.local`. It
  /// differs from [hostname] when another device already had the name, and is
  /// empty when the Quark does not say.
  final String advertisedHostname;

  /// The name in front of `.local`: [advertisedHostname] when the Quark gave
  /// one, otherwise [hostname].
  String get networkName =>
      advertisedHostname.isEmpty ? hostname : advertisedHostname;
}
