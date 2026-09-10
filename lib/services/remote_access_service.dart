import 'dart:convert';

import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

class RemoteAccessStatus {
  final bool enabled;
  final String? remoteUrl;

  const RemoteAccessStatus({required this.enabled, this.remoteUrl});

  factory RemoteAccessStatus.fromJson(Map<String, dynamic> json) =>
      RemoteAccessStatus(
        enabled: json['enabled'] as bool? ?? false,
        remoteUrl: json['remoteUrl'] as String?,
      );
}

class RemoteAccessService with AuthenticatedService {
  static final RemoteAccessService instance = RemoteAccessService._();
  RemoteAccessService._();

  static Map<String, String> get _authHeaders => instance.authHeaders;

  static Future<RemoteAccessStatus> getStatus() async {
    final uri = apiBaseUri.resolve('/api/v0/settings/remote-access');
    final response = await sharedHttpClient.get(uri, headers: _authHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        'Failed to get remote access status',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return RemoteAccessStatus.fromJson(json);
  }

  static Future<RemoteAccessStatus> enable() async {
    final uri = apiBaseUri.resolve('/api/v0/settings/remote-access');
    final response = await sharedHttpClient.post(
      uri,
      headers: {'Content-Type': 'application/json', ..._authHeaders},
      body: jsonEncode(<String, dynamic>{}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = jsonDecode(response.body) as Map<String, dynamic>?;
      throwApiError(
        response.statusCode,
        body?['error'],
        'Failed to enable remote access',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return RemoteAccessStatus.fromJson(json);
  }

  static Future<RemoteAccessStatus> disable() async {
    final uri = apiBaseUri.resolve('/api/v0/settings/remote-access');
    final response = await sharedHttpClient.delete(uri, headers: _authHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = jsonDecode(response.body) as Map<String, dynamic>?;
      throwApiError(
        response.statusCode,
        body?['error'],
        'Failed to disable remote access',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return RemoteAccessStatus.fromJson(json);
  }
}
