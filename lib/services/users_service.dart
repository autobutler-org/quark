import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quark/models/user_account.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The account routes an admin uses, under `/api/v0/admin`. The Quark answers
/// anyone else with 403.
///
/// A refusal the Quark explains in its own words, such as "no account has
/// that username", goes through [throwApiError], which passes that text on.
/// Two statuses get the app's copy instead: 403 reads as a permission failure
/// through [Errors], and a 409 on an action guarded by the last-admin rule
/// becomes [Errors.lastAdmin].
class UsersService with AuthenticatedService {
  UsersService._();
  static final UsersService instance = UsersService._();

  /// Every account on the Quark, pending requests included.
  static Future<List<UserAccount>> list() async {
    final response = await instance.authenticatedGet(
      apiBaseUri.resolve('/api/v0/admin/users'),
    );
    _check(response, 'list accounts');
    return (jsonDecode(response.body) as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(UserAccount.fromJson)
        .toList(growable: false);
  }

  /// Makes [username] an admin. Only an active account can be promoted.
  static Future<void> promote(String username) async {
    final response = await instance.authenticatedPut(
      _accountUri('/api/v0/admin/promote', username),
    );
    _check(response, 'promote $username');
  }

  /// Stops [username] being an admin. Refused while they are the last active
  /// admin.
  static Future<void> demote(String username) async {
    final response = await instance.authenticatedPut(
      _accountUri('/api/v0/admin/demote', username),
    );
    _check(response, 'demote $username', lastAdminGuard: true);
  }

  /// [path] with [username] as its last segment, encoded.
  static Uri _accountUri(String path, String username) =>
      apiBaseUri.resolve('$path/${Uri.encodeComponent(username)}');

  /// Throws for a refused [response]. [lastAdminGuard] marks a call the Quark
  /// refuses with 409 when it would leave no active admin.
  static void _check(
    http.Response response,
    String context, {
    bool lastAdminGuard = false,
  }) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return;
    if (status == 409 && lastAdminGuard) {
      throw MessageException(Errors.lastAdmin);
    }
    if (status == 403) throw ApiException(status, context);
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
