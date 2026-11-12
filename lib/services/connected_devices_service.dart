import 'dart:convert';

import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// A client that has talked to this Quark, one per IP address and
/// User-Agent, as `/api/v0/devices` lists it.
class ConnectedDevice {
  /// Creates a device record.
  const ConnectedDevice({
    required this.id,
    required this.ipAddress,
    required this.userAgent,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.requestCount,
    this.current = false,
  });

  factory ConnectedDevice.fromJson(Map<String, dynamic> json) {
    return ConnectedDevice(
      id: json['id'] as int,
      ipAddress: json['ipAddress'] as String,
      userAgent: json['userAgent'] as String? ?? '',
      firstSeenAt: DateTime.parse(json['firstSeenAt'] as String),
      lastSeenAt: DateTime.parse(json['lastSeenAt'] as String),
      requestCount: json['requestCount'] as int,
      // Absent from a Quark older than #2051.
      current: json['current'] as bool? ?? false,
    );
  }

  final int id;
  final String ipAddress;
  final String userAgent;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final int requestCount;

  /// Whether this is the client that asked for the list.
  final bool current;
}

/// Calls `/api/v0/devices`: the clients that have connected to this Quark, and removing one.
class ConnectedDevicesService with AuthenticatedService {
  static final ConnectedDevicesService _instance = ConnectedDevicesService._();
  ConnectedDevicesService._();
  static ConnectedDevicesService get instance => _instance;

  /// api: GET /api/v0/devices
  static Future<List<ConnectedDevice>> listDevices() async {
    final uri = apiBaseUri.resolve('/api/v0/devices');
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to fetch devices');
    }
    final decoded = jsonDecode(response.body);

    // Accept both [{...}] and {"data": [{...}]}
    final List<dynamic> data;
    if (decoded is List<dynamic>) {
      data = decoded;
    } else if (decoded is Map<String, dynamic> && decoded['data'] is List) {
      data = decoded['data'] as List<dynamic>;
    } else {
      throw const FormatException('Invalid connected devices response format');
    }

    return data
        .cast<Map<String, dynamic>>()
        .map(ConnectedDevice.fromJson)
        .toList(growable: false);
  }

  /// api: DELETE /api/v0/devices/{id}
  static Future<void> deleteDevice(int id) async {
    final uri = apiBaseUri.resolve('/api/v0/devices/$id');
    final response = await instance.authenticatedDelete(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to delete device');
    }
  }
}
