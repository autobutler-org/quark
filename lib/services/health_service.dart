import 'dart:convert';

import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

class HealthStatus {
  const HealthStatus({
    required this.healthy,
    required this.alerts,
    required this.cpuPercent,
    required this.cpuCorePercents,
    required this.memPercent,
    required this.memUsedBytes,
    required this.memTotalBytes,
    required this.diskPercent,
    required this.diskUsedBytes,
    required this.diskTotalBytes,
    required this.temperatureCelsius,
    this.hostname = '',
  });

  factory HealthStatus.fromJson(Map<String, dynamic> json) {
    return HealthStatus(
      healthy: json['healthy'] as bool? ?? true,
      alerts:
          (json['alerts'] as List<dynamic>?)?.cast<String>().toList(
            growable: false,
          ) ??
          const [],
      cpuPercent: (json['cpuPercent'] as num?)?.toDouble() ?? 0,
      cpuCorePercents:
          (json['cpuCorePercents'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList(growable: false) ??
          const [],
      memPercent: (json['memPercent'] as num?)?.toDouble() ?? 0,
      memUsedBytes: (json['memUsedBytes'] as num?)?.toInt() ?? 0,
      memTotalBytes: (json['memTotalBytes'] as num?)?.toInt() ?? 0,
      diskPercent: (json['diskPercent'] as num?)?.toDouble() ?? 0,
      diskUsedBytes: (json['diskUsedBytes'] as num?)?.toInt() ?? 0,
      diskTotalBytes: (json['diskTotalBytes'] as num?)?.toInt() ?? 0,
      temperatureCelsius: (json['temperatureCelsius'] as num?)?.toDouble() ?? 0,
      hostname: json['hostname'] as String? ?? '',
    );
  }

  final bool healthy;
  final List<String> alerts;
  final double cpuPercent;
  final List<double> cpuCorePercents;
  final int memUsedBytes;
  final int memTotalBytes;
  final double memPercent;
  final double diskPercent;
  final int diskUsedBytes;
  final int diskTotalBytes;
  final double temperatureCelsius;

  /// The OS hostname of the quark device (e.g. "openclaw").
  /// Used to display accurate LAN mount paths in Settings.
  final String hostname;
}

/// Calls `/api/v0/health` for the device metrics the Health page shows.
class HealthService with AuthenticatedService {
  static final HealthService _instance = HealthService._();
  HealthService._();
  static HealthService get instance => _instance;

  static Future<HealthStatus> getHealth() async {
    final uri = apiBaseUri.resolve('/api/v0/health');
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to fetch health');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid health response format');
    }

    final data = decoded['data'];
    if (data is Map<String, dynamic>) {
      return HealthStatus.fromJson(data);
    }

    return HealthStatus.fromJson(decoded);
  }
}
