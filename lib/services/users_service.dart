import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quark/models/user_account.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The account routes an admin uses, under `/api/v0/admin`, and the
/// access-requests setting. The Quark answers anyone else with 403.
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

  /// Approves the pending request from [username], who can then sign in.
  static Future<void> approve(String username) async {
    final response = await instance.authenticatedPut(
      _accountUri('/api/v0/admin/approve', username),
    );
    _check(response, 'approve $username');
  }

  /// Denies the pending request from [username]. The username is free again.
  static Future<void> deny(String username) async {
    final response = await instance.authenticatedPut(
      _accountUri('/api/v0/admin/deny', username),
    );
    _check(response, 'deny $username');
  }

  /// Turns [username]'s account off (#1909): it keeps its files and shares
  /// but cannot sign in, and its sessions end. Refused for your own account,
  /// and while it is the last active admin.
  static Future<void> disable(String username) async {
    final response = await instance.authenticatedPut(
      _accountUri('/api/v0/admin/disable', username),
    );
    _check(response, 'disable $username', lastAdminGuard: true);
  }

  /// Turns [username]'s account back on, with everything it had.
  static Future<void> enable(String username) async {
    final response = await instance.authenticatedPut(
      _accountUri('/api/v0/admin/enable', username),
    );
    _check(response, 'enable $username');
  }

  /// Deletes [username]'s account (#1909). The files it owned stay on the
  /// Quark and become the signed-in admin's. Returns how many owner rows
  /// moved. Refused for your own account, and while it is the last active
  /// admin.
  static Future<int> delete(String username) async {
    final response = await instance.authenticatedDelete(
      _accountUri('/api/v0/admin/users', username),
    );
    _check(response, 'delete $username', lastAdminGuard: true);
    final body = jsonDecode(response.body);
    return body is Map
        ? (body['ownerRowsReassigned'] as num?)?.toInt() ?? 0
        : 0;
  }

  /// Whether the Quark's sign-in page offers to request an account, as
  /// `GET /auth/status` reports it.
  static Future<bool> accessRequestsEnabled() async =>
      (await AuthService.checkStatus()).accessRequestsEnabled;

  /// Turns account requests on or off, and returns the setting the Quark
  /// saved.
  static Future<bool> setAccessRequestsEnabled(bool enabled) async {
    final response = await instance.authenticatedPut(
      apiBaseUri.resolve('/api/v0/settings/access-requests'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'enabled': enabled}),
    );
    _check(response, 'set access requests');
    final body = jsonDecode(response.body);
    return body is Map ? body['enabled'] as bool? ?? enabled : enabled;
  }

  /// Creates an active account named [username] with the initial [password]
  /// (#1873), and a folder named after it that only it and the admins can
  /// open when [createFolder] is set. Returns the new account.
  ///
  /// The account has no recovery phrase until its first sign-in, which is
  /// when the Quark returns one. A taken username or an existing folder is a
  /// 409 whose text the Quark writes, passed on as is.
  static Future<UserAccount> create({
    required String username,
    required String password,
    required bool createFolder,
  }) async {
    final response = await instance.authenticatedPost(
      apiBaseUri.resolve('/api/v0/admin/users'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'createFolder': createFolder,
      }),
    );
    _check(response, 'create $username');
    return UserAccount.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
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
