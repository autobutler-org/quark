import 'dart:convert';

import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

class RemoteAccessStatus {
  /// The Quark's setting: remote access was switched on.
  final bool enabled;

  /// Whether the Tailscale node has actually joined the tailnet. An enabled
  /// Quark that has not is still connecting, or failing — see [error].
  final bool connected;

  /// Set only when [connected].
  final String? remoteUrl;

  /// The Quark's last failure to start remote access, for logs only. It is a
  /// Go error's text, so the UI shows [Errors.remoteAccessFailing] instead.
  final String? error;

  const RemoteAccessStatus({
    required this.enabled,
    this.connected = false,
    this.remoteUrl,
    this.error,
  });

  factory RemoteAccessStatus.fromJson(Map<String, dynamic> json) =>
      RemoteAccessStatus(
        enabled: json['enabled'] as bool? ?? false,
        connected: json['connected'] as bool? ?? false,
        remoteUrl: json['remoteUrl'] as String?,
        error: json['error'] as String?,
      );
}

/// Calls `/api/v0/settings/remote-access` to read, enable and disable remote access.
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

  /// Asks the Quark for a key that adds this device to its household
  /// (`POST /settings/remote-access/devices`, #2359). Call it on the home
  /// network. A Quark older than #2359 answers 404.
  static Future<DevicePairing> pairDevice() async {
    final uri = apiBaseUri.resolve('/api/v0/settings/remote-access/devices');
    final response = await sharedHttpClient.post(uri, headers: _authHeaders);
    if (response.statusCode == 404) {
      throw ApiException(404, 'Quark has no pairing endpoint');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = jsonDecode(response.body) as Map<String, dynamic>?;
      throwApiError(response.statusCode, body?['error'], 'Failed to pair');
    }
    return DevicePairing.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}

/// What a device needs to join its Quark's household and reach the Quark.
class DevicePairing {
  /// Creates a pairing.
  const DevicePairing({
    required this.authKey,
    required this.controlUrl,
    required this.quarkAddress,
  });

  /// Parses the `POST /settings/remote-access/devices` response.
  factory DevicePairing.fromJson(Map<String, dynamic> json) => DevicePairing(
    authKey: json['authKey'] as String? ?? '',
    controlUrl: json['controlUrl'] as String? ?? '',
    quarkAddress: json['quarkAddress'] as String? ?? '',
  );

  /// A single-use Headscale pre-auth key.
  final String authKey;

  /// The Headscale server to register with.
  final String controlUrl;

  /// The Quark's URL on the tailnet, `http://100.x.y.z:80`.
  final String quarkAddress;
}
