import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quark/models/path_grant.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The sharing routes under `/api/v0/access` (#1911), open to any signed-in
/// account.
///
/// Every refusal the Quark sends from these routes is written for the person
/// sharing, such as "only the owner or an admin can change sharing" or "you
/// can't remove your own ownership; ask another owner or an admin", so
/// [throwApiError] passes it on.
class SharingService with AuthenticatedService {
  SharingService._();
  static final SharingService instance = SharingService._();

  /// Who has access to [relPath] on [deviceSerial], and whether the signed-in
  /// account may change it. A reader or writer is refused with 403.
  static Future<PathAccess> load({
    required String deviceSerial,
    required String relPath,
  }) async {
    final response = await instance.authenticatedGet(
      _accessUri.replace(
        queryParameters: {'serial': deviceSerial, 'relPath': relPath},
      ),
    );
    return _access(response, 'load access');
  }

  /// Gives the account [userId] or the group [groupId] [level] access to the
  /// path, `read`, `write` or `owner`, or changes the level it has. Answers
  /// with the path's access afterward.
  static Future<PathAccess> grant({
    required String deviceSerial,
    required String relPath,
    int? userId,
    int? groupId,
    required String level,
  }) async {
    final response = await instance.authenticatedPut(
      _accessUri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'deviceSerial': deviceSerial,
        'relPath': relPath,
        'userId': ?userId,
        'groupId': ?groupId,
        'level': level,
      }),
    );
    return _access(response, 'grant access');
  }

  /// Removes the access set on the path for the account [userId] or the group
  /// [groupId]. Answers with the path's access afterward.
  static Future<PathAccess> revoke({
    required String deviceSerial,
    required String relPath,
    int? userId,
    int? groupId,
  }) async {
    final response = await instance.authenticatedDelete(
      _accessUri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'deviceSerial': deviceSerial,
        'relPath': relPath,
        'userId': ?userId,
        'groupId': ?groupId,
      }),
    );
    return _access(response, 'revoke access');
  }

  /// Every account and group a path can be shared with.
  static Future<SharePrincipals> principals() async {
    final response = await instance.authenticatedGet(
      apiBaseUri.resolve('/api/v0/access/principals'),
    );
    _check(response, 'list principals');
    return SharePrincipals.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Uri get _accessUri => apiBaseUri.resolve('/api/v0/access');

  static PathAccess _access(http.Response response, String context) {
    _check(response, context);
    return PathAccess.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Throws for a refused [response], with the Quark's own words when it
  /// sent them.
  static void _check(http.Response response, String context) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return;
    throwApiError(status, _errorText(response.body), context);
  }

  static Object? _errorText(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? decoded['error'] : null;
    } on FormatException {
      return null;
    }
  }
}
