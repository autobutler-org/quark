import 'dart:convert';

import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

class ConnectedDevice {
  const ConnectedDevice({
    required this.id,
    required this.ipAddress,
    required this.userAgent,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.requestCount,
  });

  factory ConnectedDevice.fromJson(Map<String, dynamic> json) {
    return ConnectedDevice(
      id: json['id'] as int,
      ipAddress: json['ipAddress'] as String,
      userAgent: json['userAgent'] as String? ?? '',
      firstSeenAt: DateTime.parse(json['firstSeenAt'] as String),
      lastSeenAt: DateTime.parse(json['lastSeenAt'] as String),
      requestCount: json['requestCount'] as int,
    );
  }

  final int id;
  final String ipAddress;
  final String userAgent;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final int requestCount;
}

class ConnectedDevicesService with AuthenticatedService {
  static final ConnectedDevicesService _instance = ConnectedDevicesService._();
  ConnectedDevicesService._();
  static ConnectedDevicesService get instance => _instance;

  static Map<String, String> get _authHeaders => instance.authHeaders;

  static Future<List<ConnectedDevice>> listDevices() async {
    final uri = apiBaseUri.resolve('/api/v0/devices');
    final response = await sharedHttpClient.get(uri, headers: _authHeaders);
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

  static Future<void> deleteDevice(int id) async {
    final uri = apiBaseUri.resolve('/api/v0/devices/$id');
    final response = await sharedHttpClient.delete(uri, headers: _authHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to delete device');
    }
  }
}
