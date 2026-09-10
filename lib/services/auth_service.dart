import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// Result of a successful [AuthService.checkStatus] call.
class AuthStatus {
  /// Whether the quark has been set up with a local account.
  final bool setupComplete;

  const AuthStatus({required this.setupComplete});
}

/// Result of [AuthService.setup] — shown once, must be surfaced to the user.
class SetupResult {
  final String sessionToken;

  /// Recovery phrase shown exactly once. Store it somewhere safe.
  final String recoveryPhrase;

  const SetupResult({required this.sessionToken, required this.recoveryPhrase});
}

/// Result of [AuthService.login].
class LoginResult {
  final String sessionToken;
  const LoginResult({required this.sessionToken});
}

/// Result of [AuthService.deleteAccount] and [AuthService.resetQuark].
class DeleteAccountResult {
  /// Whether stored files survived the call and are still on the Quark.
  ///
  /// The Quark decides this rather than the app deriving it from what it
  /// asked for: one place gets to say what counts as data left behind. True
  /// after an account-only deletion, which is the default path, so the person
  /// least expecting it is the one who meets it.
  final bool filesRetained;

  const DeleteAccountResult({required this.filesRetained});
}

/// How long an auth request may go unanswered before the Quark counts as
/// unreachable.
///
/// These all hit a local device over a LAN and return a few bytes, so anything
/// slower than this is a dead host, not a slow one. Bounds the whole request,
/// not just the connect phase, so a host that accepts the connection and then
/// goes silent still fails fast. [isQuarkUnreachableError] treats the resulting
/// [TimeoutException] as unreachable and routes to the disconnected UI.
const Duration kAuthRequestTimeout = Duration(seconds: 5);

/// The client every auth call goes out through. Overridable in tests.
///
/// Defaults to the session-wide [sharedHttpClient], so auth calls reuse the
/// connection the rest of the app is already holding open. Nothing here closes
/// the client it gets back.
@visibleForTesting
http.Client Function() authHttpClientFactory = () => sharedHttpClient;

/// Communicates with the quark auth API.
class AuthService {
  static Uri get _baseUri => Uri.parse(apiBaseUrl);

  /// Checks whether initial setup has been completed on the quark.
  static Future<AuthStatus> checkStatus() async {
    final uri = _baseUri.resolve('/api/v0/auth/status');
    final response = await authHttpClientFactory()
        .get(uri)
        .timeout(kAuthRequestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to check auth status');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return AuthStatus(setupComplete: body['setup'] as bool? ?? false);
  }

  /// Creates the owner account on first boot.
  /// Returns a [SetupResult] containing the session token and recovery phrase.
  /// The recovery phrase is shown exactly once — the caller must surface it.
  static Future<SetupResult> setup({
    required String username,
    required String password,
  }) async {
    final uri = _baseUri.resolve('/api/v0/auth/setup');
    final response = await authHttpClientFactory()
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(kAuthRequestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = _tryDecodeError(response.body);
      throwApiError(response.statusCode, body, 'Setup failed');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['token'] as String;
    final phrase = body['recoveryPhrase'] as String;
    await AppSettings.instance.setSessionToken(token);
    await AppSettings.instance.setUsername(username);
    return SetupResult(sessionToken: token, recoveryPhrase: phrase);
  }

  /// Authenticates with username and password, returns a session token.
  static Future<LoginResult> login({
    required String username,
    required String password,
  }) async {
    final uri = _baseUri.resolve('/api/v0/auth/login');
    final response = await authHttpClientFactory()
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(kAuthRequestTimeout);
    if (response.statusCode == 401) {
      throw const MessageException('Invalid username or password.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = _tryDecodeError(response.body);
      throwApiError(response.statusCode, body, 'Login failed');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['token'] as String;
    await AppSettings.instance.setSessionToken(token);
    await AppSettings.instance.setUsername(username);
    return LoginResult(sessionToken: token);
  }

  /// Resets the password using the recovery phrase and returns a new session.
  static Future<LoginResult> recover({
    required String recoveryPhrase,
    required String newPassword,
  }) async {
    final uri = _baseUri.resolve('/api/v0/auth/recover');
    final response = await authHttpClientFactory()
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'recoveryPhrase': recoveryPhrase,
            'newPassword': newPassword,
          }),
        )
        .timeout(kAuthRequestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = _tryDecodeError(response.body);
      throwApiError(response.statusCode, body, 'Recovery failed');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['token'] as String;
    await AppSettings.instance.setSessionToken(token);
    return LoginResult(sessionToken: token);
  }

  /// Logs out — clears the in-memory session token and notifies the server.
  static Future<void> logout() async {
    final token = AppSettings.instance.sessionToken;
    await AppSettings.instance.setSessionToken(null);
    if (token == null) return;
    try {
      final uri = _baseUri.resolve('/api/v0/auth/logout');
      await authHttpClientFactory()
          .post(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(kAuthRequestTimeout);
    } catch (_) {
      // Best-effort — token is already cleared locally.
    }
  }

  /// Deletes the signed-in user's account on the current Quark, and nothing
  /// else (#1762).
  ///
  /// This is the App Store Guideline 5.1.1(v) path. It selects `account` and
  /// none of the three appliance-wide aspects the endpoint also offers: those
  /// are a factory reset, they go through [resetQuark], and nothing reachable
  /// from "Delete account" may reach them. Two intents, two call sites, so no
  /// stray parameter can turn one into the other.
  ///
  /// [confirmUsername] is what the user typed to confirm. The Quark answers
  /// 400 unless it equals the authenticated username, so holding a session is
  /// not on its own consent to delete the account.
  static Future<DeleteAccountResult> deleteAccount({
    required String confirmUsername,
  }) => _deleteAspects(
    confirmUsername: confirmUsername,
    aspects: const {'account': 'true'},
    context: 'Account deletion failed',
  );

  /// Factory-resets the current Quark, wiping the selected aspects (#1762).
  ///
  /// A different intent from [deleteAccount] and a different surface: this
  /// leaves nothing of anybody's behind, so [database] and [files] are what a
  /// caller is normally here for. [devices] additionally reaches the Quark
  /// data directory on attached external drives, which is why it is never a
  /// default — a drive plugged in for unrelated reasons must not be wiped
  /// because someone accepted a form as it came.
  ///
  /// `account` is not selected: [database] takes the user rows with it, and a
  /// reset that selected nothing but the account would be a deletion wearing a
  /// reset's copy. Passing all three as false is a 400 from the Quark.
  static Future<DeleteAccountResult> resetQuark({
    required String confirmUsername,
    required bool database,
    required bool files,
    required bool devices,
  }) => _deleteAspects(
    confirmUsername: confirmUsername,
    aspects: {
      'database': database.toString(),
      'files': files.toString(),
      'devices': devices.toString(),
    },
    context: 'Quark reset failed',
  );

  /// Issues the delete with [aspects] selected, and forgets the local session.
  ///
  /// The Quark revokes the session either way, so the token is dropped on
  /// success and the caller routes the user out. Failure keeps it: nothing was
  /// destroyed and the session still works.
  static Future<DeleteAccountResult> _deleteAspects({
    required String confirmUsername,
    required Map<String, String> aspects,
    required String context,
  }) async {
    final token = AppSettings.instance.sessionToken;
    if (token == null) throw const UnauthorizedException();
    final uri = _baseUri
        .resolve('/api/v0/auth/account')
        .replace(queryParameters: {...aspects, 'confirm': confirmUsername});
    final response = await authHttpClientFactory()
        .delete(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(kAuthRequestTimeout);
    // A session the Quark no longer honors is handled the way the rest of the
    // app handles one, rather than as a failure: the token is dropped and the
    // caller routes the user out. Reading it as an error would put the Quark's
    // own "not authenticated" text in front of someone who did nothing wrong
    // and leave them parked on a page they can no longer use.
    if (response.statusCode == 401) {
      await _forgetLocalSession();
      throw const UnauthorizedException();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = _tryDecodeError(response.body);
      throwApiError(response.statusCode, body, context);
    }
    await _forgetLocalSession();
    return DeleteAccountResult(
      filesRetained: _decodeFilesRetained(response.body),
    );
  }

  /// Reads `filesRetained` out of a success body.
  ///
  /// Absent means false: an older Quark that does not report it is one whose
  /// answer cannot support the claim that files were left behind, and the
  /// notice is only worth showing when it is certainly true.
  static bool _decodeFilesRetained(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return decoded['filesRetained'] as bool? ?? false;
    } catch (_) {
      debugPrint('[auth_service.dart] Unreadable deletion response');
    }
    return false;
  }

  /// Drops the current Quark's session and the username that went with it.
  ///
  /// Only this Quark's. The user may be signed in to others, and those
  /// accounts are still there.
  static Future<void> _forgetLocalSession() async {
    await AppSettings.instance.setUsername(null);
    await AppSettings.instance.setSessionToken(null);
  }

  static String? _tryDecodeError(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      return decoded['error'] as String? ?? decoded['message'] as String?;
    } catch (_) {
      debugPrint('[auth_service.dart] Error in catch block');
      return null;
    }
  }
}
