import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quark/models/restart_status.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The admin-only restart API: `/api/v0/admin/restart` (#4019).
///
/// A 409 carries the Quark's own sentence for why it can't restart now, so a
/// 4xx goes through [throwApiError]. A 5xx is a diagnostic and becomes a bare
/// [ApiException].
class RestartService with AuthenticatedService {
  RestartService._();
  static final RestartService instance = RestartService._();

  // A getter, not a field: the base follows the active host.
  /// api: none
  static Uri get _uri => apiBaseUri.resolve('/api/v0/admin/restart');

  /// Whether the Quark can restart itself, and why not when it can't.
  ///
  /// api: GET /api/v0/admin/restart
  static Future<RestartStatus> getStatus() async {
    final response = await instance.authenticatedGet(_uri);
    _check(response, 'load restart status');
    return RestartStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Asks the Quark to restart.
  ///
  /// The answer is an empty 200 sent about two seconds before the process
  /// exits, so there is no body to read.
  ///
  /// api: POST /api/v0/admin/restart
  static Future<void> restart() async {
    final response = await instance.authenticatedPost(_uri);
    _check(response, 'restart Quark');
  }

  static void _check(http.Response response, String context) =>
      throwUnlessOk(response, context, clientErrorsOnly: true);
}
