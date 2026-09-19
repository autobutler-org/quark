import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quark/models/ssh_access_status.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The admin-only SSH access API: `/api/v0/ssh` (#2131).
///
/// A 4xx carries the Quark's own hand-written sentence ("that key is already
/// allowed"), so it goes through [throwApiError]. A 5xx carries the helper's
/// output, which is a diagnostic, so it becomes a bare [ApiException].
class SshAccessService with AuthenticatedService {
  SshAccessService._();
  static final SshAccessService instance = SshAccessService._();

  static const _json = {'Content-Type': 'application/json'};

  /// Whether SSH access can be managed, whether it is on, and the keys.
  static Future<SshAccessStatus> getStatus() async {
    final response = await instance.authenticatedGet(
      apiBaseUri.resolve('/api/v0/ssh/status'),
    );
    _check(response, 'load SSH access');
    return SshAccessStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Turns SSH access on or off.
  static Future<void> setEnabled(bool enabled) async {
    final response = await instance.authenticatedPut(
      apiBaseUri.resolve('/api/v0/ssh/enabled'),
      headers: _json,
      body: jsonEncode({'enabled': enabled}),
    );
    _check(response, 'change SSH access');
  }

  /// Allows [key], one public key line, to sign in.
  static Future<void> addKey(String key) async {
    final response = await instance.authenticatedPost(
      apiBaseUri.resolve('/api/v0/ssh/keys'),
      headers: _json,
      body: jsonEncode({'key': key}),
    );
    _check(response, 'add the SSH key');
  }

  /// Stops the key with [fingerprint] signing in.
  static Future<void> removeKey(String fingerprint) async {
    final response = await instance.authenticatedDelete(
      apiBaseUri.replace(
        path: '/api/v0/ssh/keys',
        queryParameters: {'fingerprint': fingerprint},
      ),
    );
    _check(response, 'remove the SSH key');
  }

  /// Sets the quark login account's password.
  static Future<void> setPassword(String password) async {
    final response = await instance.authenticatedPut(
      apiBaseUri.resolve('/api/v0/ssh/password'),
      headers: _json,
      body: jsonEncode({'password': password}),
    );
    _check(response, 'set the SSH password');
  }

  /// Clears the quark login account's password.
  static Future<void> clearPassword() async {
    final response = await instance.authenticatedDelete(
      apiBaseUri.resolve('/api/v0/ssh/password'),
    );
    _check(response, 'clear the SSH password');
  }

  static void _check(http.Response response, String context) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return;
    if (status >= 400 && status < 500) {
      Object? message;
      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) message = body['error'];
      } on FormatException {
        message = null;
      }
      throwApiError(status, message, context);
    }
    throw ApiException(status, context);
  }
}
