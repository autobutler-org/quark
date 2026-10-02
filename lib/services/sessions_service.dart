import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quark/models/auth_session.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The session-management API: `/api/v0/auth/sessions` (#1663).
///
/// The Quark's `error` on these routes is a Go error's text, not copy written
/// for a user, so a failure is always a bare [ApiException].
class SessionsService with AuthenticatedService {
  SessionsService._();

  /// The one instance, which carries the auth headers.
  static final SessionsService instance = SessionsService._();

  /// The account's active sessions, with the one in use marked current.
  static Future<List<AuthSession>> list() async {
    final response = await instance.authenticatedGet(
      apiBaseUri.resolve('/api/v0/auth/sessions'),
    );
    _check(response, 'load sessions');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['sessions'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AuthSession.fromJson)
        .toList(growable: false);
  }

  /// Signs out the session with [id].
  static Future<void> revoke(String id) async {
    final response = await instance.authenticatedDelete(
      apiBaseUri.resolve('/api/v0/auth/sessions/${Uri.encodeComponent(id)}'),
    );
    _check(response, 'revoke the session');
  }

  /// Signs out every session of the account except the one in use.
  static Future<void> revokeOthers() async {
    final response = await instance.authenticatedDelete(
      apiBaseUri.resolve('/api/v0/auth/sessions'),
    );
    _check(response, 'revoke the other sessions');
  }

  static void _check(http.Response response, String context) {
    final status = response.statusCode;
    if (status < 200 || status >= 300) throw ApiException(status, context);
  }
}
