import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quark/models/repair_status.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The admin-only repair API: `/api/v0/admin/repair` (#2121).
///
/// A 409 carries the Quark's own sentence for why repair is unavailable, so a
/// 4xx goes through [throwApiError]. A 5xx is a diagnostic and becomes a bare
/// [ApiException].
class RepairService with AuthenticatedService {
  RepairService._();
  static final RepairService instance = RepairService._();

  // A getter, not a field: the base follows the active host.
  static Uri get _uri => apiBaseUri.resolve('/api/v0/admin/repair');

  /// Whether the installation can be repaired, and why not when it can't.
  static Future<RepairStatus> getStatus() async {
    final response = await instance.authenticatedGet(_uri);
    _check(response, 'load repair status');
    return RepairStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Asks the Quark to restart, which reapplies its system setup as root.
  ///
  /// The answer is an empty 200 sent just before the process exits, so there
  /// is no body to read.
  static Future<void> repair() async {
    final response = await instance.authenticatedPost(_uri);
    _check(response, 'repair the installation');
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
