import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:quark/controllers/chat_keys_controller.dart';
import 'package:quark/models/chat_keys.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_secret.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/feature_flags_service.dart';
import 'package:quark/services/settings_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:sodium/sodium_sumo.dart' show SecureKey;

/// Result of a successful [AuthService.checkStatus] call.
class AuthStatus {
  /// Whether the quark has been set up with a local account.
  final bool setupComplete;

  /// The signed-in username, or null when the call carried no valid session.
  final String? username;

  /// Whether the signed-in user is an admin. False without a valid session.
  ///
  /// Only decides what the app shows; the Quark still refuses admin-only
  /// requests from anyone else.
  final bool isAdmin;

  /// The signed-in account's id, or null without a valid session.
  final int? userId;

  /// The signed-in account's profile picture version in Unix milliseconds,
  /// or null when it has none.
  final int? avatarUpdatedAt;

  /// Whether the Quark's sign-in page may offer to request an account (#1908).
  /// False before setup, and when the Quark does not say.
  final bool accessRequestsEnabled;

  const AuthStatus({
    required this.setupComplete,
    this.username,
    this.isAdmin = false,
    this.userId,
    this.avatarUpdatedAt,
    this.accessRequestsEnabled = false,
  });
}

/// Result of [AuthService.setup] — shown once, must be surfaced to the user.
class SetupResult {
  final String sessionToken;

  /// Recovery phrase shown exactly once. Store it somewhere safe. The app
  /// generated it, unless the Quark is too old to take a recovery key and
  /// made its own (#2430).
  final String recoveryPhrase;

  const SetupResult({required this.sessionToken, required this.recoveryPhrase});
}

/// Result of [AuthService.login] and [AuthService.recover].
class LoginResult {
  final String sessionToken;

  /// The account the session is for.
  final String username;

  /// A recovery phrase to show the user once.
  ///
  /// From [AuthService.login]: the phrase the app just gave the account in
  /// place of one the Quark made (#2430), or, from a Quark too old for that,
  /// the Quark's own phrase on the first sign-in of an account an admin
  /// created (#1873). Non-null means the session has not been stored yet: the
  /// caller shows the phrase, then calls [AuthService.acceptSession] once it
  /// has been acknowledged.
  ///
  /// From [AuthService.recover]: the new phrase a recovery with an old,
  /// Quark-made phrase gave the account. That session is stored already.
  final String? recoveryPhrase;

  const LoginResult({
    required this.sessionToken,
    required this.username,
    this.recoveryPhrase,
  });
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

/// The client a host probe goes out through, built for the host being probed
/// rather than the active one. Overridable in tests.
///
/// Its caller closes what this returns, so it may not hand back the shared
/// client.
@visibleForTesting
http.Client Function(String hostAddress) hostProbeHttpClientFactory =
    buildLocalTrustHttpClient;

/// The reachability check the host forms run before saving an address.
///
/// A `var` rather than a direct call so a widget test can answer for a Quark
/// that is not there, and so a test about something else can say yes without
/// standing a server up.
Future<bool> Function(String hostAddress) hostReachabilityProbe =
    AuthService.isReachable;

/// What a sign-in does with chat keys once it has the password (#2416):
/// unwrap them, or make them when the account has none. Overridable in tests.
///
/// [recoveryPhrase] is set at a first sign-in, and [sessionToken] is the new
/// session, which the app may not have stored yet. [authSalt] is the salt the
/// sign-in's auth key was derived with, null on a Quark that still takes the
/// raw password (#2430). [phraseWrapKey] is the wrap key of a phrase the app
/// generated, and the result is the keys re-wrapped under it; see
/// [ChatKeysController.signedIn].
Future<WrappedChatKeys?> Function({
  required String password,
  String? recoveryPhrase,
  SecureKey? phraseWrapKey,
  required String sessionToken,
  Uint8List? authSalt,
})
chatKeysOnSignIn =
    ({
      required password,
      recoveryPhrase,
      phraseWrapKey,
      required sessionToken,
      authSalt,
    }) => ChatKeysController.instance.signedIn(
      password: password,
      recoveryPhrase: recoveryPhrase,
      phraseWrapKey: phraseWrapKey,
      sessionToken: sessionToken,
      authSalt: authSalt,
    );

/// Opens the account's chat keys with the recovery phrase and re-wraps them
/// under the new password, for [AuthService.recover] to send (#2416). See
/// [ChatKeysController.keysForRecovery]. Overridable in tests.
Future<WrappedChatKeys> Function({
  required String username,
  required String recoveryPhrase,
  AuthKeys? recoveryKeys,
  SecureKey? newPhraseWrapKey,
  required String newPassword,
  Uint8List? authSalt,
})
chatKeysForRecovery = ChatKeysController.instance.keysForRecovery;

/// Runs [chatKeysOnSignIn] without holding up the sign-in. Chat is not what
/// the user signed in for, and chat unlocks later from its own prompt when
/// this fails. [recovery] is the keys of a phrase the app generated, used for
/// the phrase wrap and disposed once the unlock is done.
void _unlockChatKeys({
  required String password,
  String? recoveryPhrase,
  AuthKeys? recovery,
  required String sessionToken,
  required Uint8List? authSalt,
}) {
  unawaited(
    Future(
          () => chatKeysOnSignIn(
            password: password,
            recoveryPhrase: recoveryPhrase,
            phraseWrapKey: recovery?.wrapKey,
            sessionToken: sessionToken,
            authSalt: authSalt,
          ),
        )
        .catchError((Object e) {
          debugPrint('[auth_service.dart] chat keys not unlocked: $e');
          return null;
        })
        .whenComplete(() => recovery?.dispose()),
  );
}

/// A recovery phrase the app generated, and its keys under an account's auth
/// salt (#2430). The caller disposes [keys].
typedef NewRecoveryPhrase = ({String phrase, AuthKeys keys});

/// Generates a recovery phrase and derives its keys under [salt], at the
/// cost every recovery key is derived with.
Future<NewRecoveryPhrase> _newRecoveryPhrase(Uint8List salt) async {
  final crypto = await ChatCrypto.load();
  final phrase = crypto.generateRecoveryPhrase();
  return (
    phrase: phrase,
    keys: crypto.deriveRecoveryKeys(phrase, salt, KdfParams.standard),
  );
}

/// Communicates with the quark auth API.
class AuthService {
  static Uri get _baseUri => Uri.parse(apiBaseUrl);

  /// Checks whether initial setup has been completed on the quark and, when
  /// this app holds a session, who is signed in.
  static Future<AuthStatus> checkStatus() async {
    final uri = _baseUri.resolve('/api/v0/auth/status');
    final token = AppSettings.instance.sessionToken;
    final response = await authHttpClientFactory()
        .get(
          uri,
          headers: token == null ? null : {'Authorization': 'Bearer $token'},
        )
        .timeout(kAuthRequestTimeout);
    return _readStatus(response);
  }

  /// Asks the Quark at [hostAddress] the same question, before that address
  /// is the active host.
  ///
  /// `/auth/status` is the probe because it is the one endpoint a Quark
  /// answers to a stranger: no session, no terms, nothing configured. A
  /// non-Quark that answers anyway fails on the body, which is the point —
  /// "something is listening" is not "this is your Quark".
  ///
  /// Throws whatever the attempt threw; the caller decides what unreachable
  /// means for it.
  static Future<AuthStatus> checkStatusAt(String hostAddress) async {
    final client = hostProbeHttpClientFactory(hostAddress);
    try {
      final response = await client
          .get(Uri.parse(hostAddress).resolve('/api/v0/auth/status'))
          .timeout(kAuthRequestTimeout);
      return _readStatus(response);
    } finally {
      // Built for one probe against a host that may never become active, so
      // it is closed here rather than pooled like [sharedHttpClient].
      client.close();
    }
  }

  /// Whether a Quark answers at [hostAddress].
  ///
  /// Saving an address that nothing answers on walks the user into the rest
  /// of onboarding against a dead host (#2032), so this runs first. It never
  /// throws: unreachable is the answer, not a failure.
  static Future<bool> isReachable(String hostAddress) async {
    try {
      await checkStatusAt(hostAddress);
      return true;
    } catch (_) {
      return false;
    }
  }

  static AuthStatus _readStatus(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to check auth status');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return AuthStatus(
      setupComplete: body['setup'] as bool? ?? false,
      username: body['username'] as String?,
      isAdmin: body['isAdmin'] as bool? ?? false,
      userId: (body['userId'] as num?)?.toInt(),
      avatarUpdatedAt: (body['avatarUpdatedAt'] as num?)?.toInt(),
      accessRequestsEnabled: body['accessRequestsEnabled'] as bool? ?? false,
    );
  }

  /// Fetches the signed-in user's admin flag again into [AppSettings.isAdmin],
  /// their id and picture version into [AppSettings.userId] and
  /// [AppSettings.avatarUpdatedAt], the beta feature flags into
  /// [AppSettings.featureFlags], and the Quark's theme color and the user's own
  /// into [AppSettings.themeColor] (#2740). The Quark's theme color needs no session,
  /// so it is fetched for the sign-in page too.
  ///
  /// Without a session there is no admin and no account. A failed call keeps the last known
  /// value: it only decides what the app shows, and the Quark still refuses
  /// admin-only requests from a non-admin.
  static Future<void> refreshAccount() async {
    final settings = AppSettings.instance;
    unawaited(SettingsService.refreshThemeColor());
    if (settings.sessionToken == null) {
      settings.isAdmin.value = false;
      settings.userId.value = null;
      settings.avatarUpdatedAt.value = null;
      settings.featureFlags.value = const [];
      return;
    }
    unawaited(FeatureFlagsService.refresh());
    try {
      final status = await checkStatus();
      settings.isAdmin.value = status.isAdmin;
      settings.userId.value = status.userId;
      settings.avatarUpdatedAt.value = status.avatarUpdatedAt;
      if (status.username != null) {
        await settings.setUsername(status.username);
      }
    } catch (e) {
      debugPrint('[auth_service.dart] refreshAccount failed: $e');
    }
  }

  /// Keeps [AppSettings.isAdmin] current for the life of the app.
  ///
  /// Refreshes now, whenever the session changes (sign-in, sign-out, a 401,
  /// switching Quarks), and whenever the Quark reports an account's role
  /// changed, so a demoted admin loses admin-only entries without signing out.
  /// The Quark closes the socket of the account whose role changed instead of
  /// sending it that event, so every reconnect refreshes too.
  static void watchAccount() {
    AppSettings.instance.sessionTokenNotifier.addListener(refreshAccount);
    // Switching between two Quarks that are both signed out moves no session,
    // and the sign-in page still wants the new Quark's theme color (#2740).
    AppSettings.instance.activeHostNotifier.addListener(
      SettingsService.refreshThemeColor,
    );
    EventsService.instance.events.listen((event) {
      if (event.kind == 'account_changed') refreshAccount();
      // An admin flipped a beta on or off; members follow it live (#2542).
      if (event.kind == 'feature_flag_changed') FeatureFlagsService.refresh();
      // An admin changed the Quark's default theme color (#2740).
      if (event.kind == 'public_settings_changed') {
        SettingsService.refreshThemeColor();
      }
    });
    EventsService.instance.connections.listen((_) => refreshAccount());
    EventsService.instance.start();
    refreshAccount();
  }

  /// Creates the owner account on first boot.
  /// Returns a [SetupResult] containing the session token and recovery phrase.
  /// The recovery phrase is shown exactly once — the caller must surface it.
  static Future<SetupResult> setup({
    required String username,
    required String password,
  }) async {
    final uri = _baseUri.resolve('/api/v0/auth/setup');
    final secret = await AuthSecret.resolve(
      username: username,
      password: password,
      use: AuthSecretUse.newCredential,
    );
    final mine = await _newPhraseFor(secret);
    final Map<String, dynamic> body;
    try {
      body = await _postNewAccount(
        uri,
        username: username,
        secret: secret,
        mine: mine,
        context: 'Setup failed',
      );
    } catch (_) {
      mine?.keys.dispose();
      rethrow;
    }
    final token = body['token'] as String;
    // A Quark too old to take the recovery key made its own phrase, and that
    // is the one that works.
    final theirs = body['recoveryPhrase'] as String?;
    final ours = theirs == null ? mine : null;
    if (ours == null) mine?.keys.dispose();
    await secret.accepted(username);
    if (ours != null) await AppSettings.instance.rememberRecoveryKey(username);
    await AppSettings.instance.setSessionToken(token);
    await AppSettings.instance.setUsername(username);
    _unlockChatKeys(
      password: password,
      recoveryPhrase: theirs,
      recovery: ours?.keys,
      sessionToken: token,
      authSalt: secret.salt,
    );
    return SetupResult(
      sessionToken: token,
      recoveryPhrase: theirs ?? ours!.phrase,
    );
  }

  /// Authenticates with username and password, returns a session token.
  ///
  /// The Quark is sent an auth key derived from [password], not the password
  /// (#2430); see [AuthSecret] for the accounts and Quarks that still get it.
  static Future<LoginResult> login({
    required String username,
    required String password,
  }) async {
    final uri = _baseUri.resolve('/api/v0/auth/login');
    final secret = await AuthSecret.resolve(
      username: username,
      password: password,
      use: AuthSecretUse.signIn,
    );
    final response = await authHttpClientFactory()
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, ...secret.fields()}),
        )
        .timeout(kAuthRequestTimeout);
    if (response.statusCode == 401) {
      throw const MessageException(Errors.invalidCredentials);
    }
    if (response.statusCode == 403) {
      _throwAccountRefusal(response.body, 'Login failed');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = _tryDecodeError(response.body);
      throwApiError(response.statusCode, body, 'Login failed');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['token'] as String;
    await secret.accepted(username);
    final String? phrase;
    // An account whose phrase the Quark made, and so has seen, is given one
    // the app makes (#2430). That waits for the chat keys, which have to be
    // re-wrapped under it; any other sign-in leaves them to finish on their
    // own. A Quark that does not say gets no rotation.
    if (body['legacyRecovery'] == true &&
        secret.authKey != null &&
        secret.salt != null) {
      phrase = await _rotateRecoveryPhrase(
        username: username,
        password: password,
        secret: secret,
        sessionToken: token,
      );
    } else {
      phrase = body['recoveryPhrase'] as String?;
      _unlockChatKeys(
        password: password,
        recoveryPhrase: phrase,
        sessionToken: token,
        authSalt: secret.salt,
      );
    }
    final result = LoginResult(
      sessionToken: token,
      username: username,
      recoveryPhrase: phrase,
    );
    // A recovery phrase is never shown again (#1873). Storing the token now
    // would let the router swap the login page for /files before the phrase
    // was shown, so the caller stores it with [acceptSession] once the phrase
    // has been acknowledged.
    if (phrase == null) await acceptSession(result);
    return result;
  }

  /// Gives [username] a recovery phrase the app generated, in place of one
  /// the Quark made (#2430), and returns it, or null when that failed.
  ///
  /// Unlocks the chat keys first, since their phrase wrap has to move to the
  /// new phrase, then registers the phrase's recovery key with
  /// `PUT /auth/recovery-key`, which stores the re-wrapped keys in the same
  /// transaction. The phrase is returned only once the Quark answers 204;
  /// until then the old one still works. A failure is logged and nothing
  /// else: the sign-in stands, and the next one tries again. So does one
  /// whose chat keys would not open, since only they can be re-wrapped.
  static Future<String?> _rotateRecoveryPhrase({
    required String username,
    required String password,
    required AuthSecret secret,
    required String sessionToken,
  }) async {
    final NewRecoveryPhrase mine;
    try {
      mine = await _newRecoveryPhrase(secret.salt!);
    } catch (e) {
      debugPrint('[auth_service.dart] recovery phrase not rotated: $e');
      return null;
    }
    try {
      final chatKeys = await chatKeysOnSignIn(
        password: password,
        phraseWrapKey: mine.keys.wrapKey,
        sessionToken: sessionToken,
        authSalt: secret.salt,
      );
      final response = await authHttpClientFactory()
          .put(
            _baseUri.resolve('/api/v0/auth/recovery-key'),
            headers: {
              'Authorization': 'Bearer $sessionToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              // The re-confirmation takes the auth key, never the password.
              'password': secret.authKey,
              'recoveryKey': mine.keys.authKey,
              'chatKeys': ?chatKeys?.toJson(),
            }),
          )
          .timeout(kAuthRequestTimeout);
      if (response.statusCode != 204) {
        debugPrint(
          '[auth_service.dart] recovery phrase not rotated: '
          '${response.statusCode}',
        );
        return null;
      }
      await AppSettings.instance.rememberRecoveryKey(username);
      return mine.phrase;
    } catch (e) {
      debugPrint('[auth_service.dart] recovery phrase not rotated: $e');
      return null;
    } finally {
      mine.keys.dispose();
    }
  }

  /// Stores [result]'s session and username, which is what signs the app in.
  ///
  /// [login] does this itself unless the result carries a recovery phrase.
  /// Every explicit sign-in ends here and a launch on a stored session never
  /// does, so this is also where Files is told to say "welcome back".
  static Future<void> acceptSession(LoginResult result) async {
    await AppSettings.instance.setSessionToken(result.sessionToken);
    await AppSettings.instance.setUsername(result.username);
    // Last, so the greeting is published with the name already stored. Here
    // rather than in the login page's success callback: storing the token
    // above lets the router leave /login, and a page that has been unmounted
    // by then never runs its callback (#2022).
    AppSettings.instance.greetSignIn();
  }

  /// Resets [username]'s password using that account's recovery phrase and
  /// returns a new session.
  ///
  /// The account's chat keys are opened with the phrase first and sent back
  /// re-wrapped under [newPassword] in the same request, so recovering keeps
  /// chat history (#2416). A phrase that opens nothing fails here, before the
  /// password changes.
  ///
  /// What stands in for the phrase follows `GET /auth/salt` (#2430). An
  /// account with a recovery key is sent the key derived from
  /// [recoveryPhrase], never the phrase. One without (`legacyRecovery`) has to
  /// be sent the phrase, so it is given a new one the app generates, sent as
  /// `newRecoveryKey`, and the result's [LoginResult.recoveryPhrase] carries
  /// it to show. A Quark that does not say gets the phrase, as before; once
  /// this Quark has a recovery key for [username]
  /// ([AppSettings.hasRecoveryKey]), anything but a key is refused with
  /// [Errors.recoveryPhraseDowngradeRefused].
  static Future<LoginResult> recover({
    required String username,
    required String recoveryPhrase,
    required String newPassword,
  }) async {
    // The salt asked for now is the one the Quark stores with the new key: it
    // keeps the account's salt, or assigns the one it answers here.
    final secret = await AuthSecret.resolve(
      username: username,
      password: newPassword,
      use: AuthSecretUse.newCredential,
    );
    final salt = secret.salt;
    final legacyRecovery = salt == null ? null : secret.legacyRecovery;
    if (legacyRecovery != false &&
        AppSettings.instance.hasRecoveryKey(username)) {
      throw const MessageException(Errors.recoveryPhraseDowngradeRefused);
    }
    final crypto = await ChatCrypto.load();
    final typed = legacyRecovery == false
        ? crypto.deriveRecoveryKeys(recoveryPhrase, salt!, KdfParams.standard)
        : null;
    final NewRecoveryPhrase? next;
    final http.Response response;
    try {
      next = legacyRecovery == true ? await _newRecoveryPhrase(salt!) : null;
      try {
        final chatKeys = await chatKeysForRecovery(
          username: username,
          recoveryPhrase: recoveryPhrase,
          recoveryKeys: typed,
          newPhraseWrapKey: next?.keys.wrapKey,
          newPassword: newPassword,
          authSalt: salt,
        );
        response = await authHttpClientFactory()
            .post(
              _baseUri.resolve('/api/v0/auth/recover'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'username': username,
                ..._recoveryCredential(recoveryPhrase, typed),
                ...secret.fields(
                  passwordField: 'newPassword',
                  authKeyField: 'newAuthKey',
                ),
                'newRecoveryKey': ?next?.keys.authKey,
                'chatKeys': chatKeys.toJson(),
              }),
            )
            .timeout(kAuthRequestTimeout);
      } finally {
        next?.keys.dispose();
      }
    } finally {
      typed?.dispose();
    }
    // A pending or disabled account is refused like a sign-in (#1908).
    if (response.statusCode == 403) {
      _throwAccountRefusal(response.body, 'Recovery failed');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = _tryDecodeError(response.body);
      throwApiError(response.statusCode, body, 'Recovery failed');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['token'] as String;
    await secret.accepted(username);
    if (legacyRecovery != null) {
      await AppSettings.instance.rememberRecoveryKey(username);
    }
    await AppSettings.instance.setSessionToken(token);
    await AppSettings.instance.setUsername(username);
    // ponytail: unwraps again under the new password (one more Argon2id run)
    // rather than threading the identity out of chatKeysForRecovery.
    _unlockChatKeys(
      password: newPassword,
      sessionToken: token,
      authSalt: secret.salt,
    );
    return LoginResult(
      sessionToken: token,
      username: username,
      recoveryPhrase: next?.phrase,
    );
  }

  /// [username]'s wrapped chat identity, for recovery, which has no session
  /// (#2416). The Quark checks the credential first, as `/auth/recover`
  /// does, and changes nothing. Exactly one of [recoveryPhrase] and
  /// [recoveryKey] is sent (#2430). Null when the account has no chat keys.
  ///
  /// A wrong phrase throws the Quark's own text; a pending or disabled
  /// account is refused as a sign-in is.
  static Future<WrappedChatKeys?> fetchRecoveryChatKeys({
    required String username,
    String? recoveryPhrase,
    String? recoveryKey,
  }) async {
    final uri = _baseUri.resolve('/api/v0/auth/recover/keys');
    final response = await authHttpClientFactory()
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': username,
            'recoveryPhrase': ?recoveryPhrase,
            'recoveryKey': ?recoveryKey,
          }),
        )
        .timeout(kAuthRequestTimeout);
    if (response.statusCode == 404) return null;
    if (response.statusCode == 403) {
      _throwAccountRefusal(response.body, 'Recovery failed');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = _tryDecodeError(response.body);
      throwApiError(response.statusCode, body, 'Recovery failed');
    }
    return WrappedChatKeys.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// The recovery fields of `/auth/recover`: the key of [phrase] when there
  /// is one, else the phrase itself.
  static Map<String, String> _recoveryCredential(
    String phrase,
    AuthKeys? keys,
  ) =>
      keys == null ? {'recoveryPhrase': phrase} : {'recoveryKey': keys.authKey};

  /// Asks this Quark for an account (#1908) and returns the new account's
  /// recovery phrase, which is shown once. The app generates it and sends
  /// only its recovery key (#2430), unless the Quark is too old for that and
  /// makes its own.
  ///
  /// No session comes back: an admin approves the account before it can sign
  /// in. A Quark that is not taking requests, or has not been set up, answers
  /// 404, which reads as [Errors.accessRequestsOff]. Any other refusal, such
  /// as a taken username, passes on the Quark's own text.
  static Future<String> requestAccount({
    required String username,
    required String password,
  }) async {
    final uri = _baseUri.resolve('/api/v0/auth/request-account');
    final secret = await AuthSecret.resolve(
      username: username,
      password: password,
      use: AuthSecretUse.newCredential,
    );
    final mine = await _newPhraseFor(secret);
    try {
      final body = await _postNewAccount(
        uri,
        username: username,
        secret: secret,
        mine: mine,
        context: 'Account request failed',
        notFound: Errors.accessRequestsOff,
      );
      return body['recoveryPhrase'] as String? ?? mine!.phrase;
    } finally {
      // The account's chat keys are made at its first sign-in, which has no
      // phrase to wrap them under.
      mine?.keys.dispose();
    }
  }

  /// A phrase for a new account whose auth key [secret] carries, or null for
  /// a Quark that still takes the password and so makes its own phrase.
  static Future<NewRecoveryPhrase?> _newPhraseFor(AuthSecret secret) async {
    final salt = secret.salt;
    if (secret.authKey == null || salt == null) return null;
    return _newRecoveryPhrase(salt);
  }

  /// Posts a new account's credentials to [uri] and returns the 2xx body:
  /// [secret]'s fields, and [mine]'s recovery key when there is one. A 404
  /// throws [notFound] when it is set.
  static Future<Map<String, dynamic>> _postNewAccount(
    Uri uri, {
    required String username,
    required AuthSecret secret,
    required NewRecoveryPhrase? mine,
    required String context,
    String? notFound,
  }) async {
    final response = await authHttpClientFactory()
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': username,
            ...secret.fields(),
            'recoveryKey': ?mine?.keys.authKey,
          }),
        )
        .timeout(kAuthRequestTimeout);
    if (response.statusCode == 404 && notFound != null) {
      throw MessageException(notFound);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = _tryDecodeError(response.body);
      throwApiError(response.statusCode, body, context);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// The salt [username]'s auth key is derived with, whether the account is
  /// `legacy`, with no auth key yet, and whether it is `legacyRecovery`, with
  /// no recovery key yet (#2430): `GET /auth/salt`, which needs no session.
  /// Null from a Quark that has no such endpoint; `legacyRecovery` is null
  /// from one that does not report it.
  ///
  /// An older Quark does not answer 404 alone. Without a session it refuses an
  /// unknown API path with a 401, and before setup its web fallback answers
  /// 200 with the app's `index.html`, so a 2xx with no salt in it counts too.
  static Future<({Uint8List salt, bool legacy, bool? legacyRecovery})?>
  fetchAuthSalt(String username) async {
    final response = await authHttpClientFactory()
        .get(
          _baseUri
              .resolve('/api/v0/auth/salt')
              .replace(queryParameters: {'username': username}),
        )
        .timeout(kAuthRequestTimeout);
    final status = response.statusCode;
    if (status == 401 || status == 404) return null;
    if (status < 200 || status >= 300) {
      throw ApiException(status, 'Failed to fetch the auth salt');
    }
    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      return null;
    }
    if (body is! Map) return null;
    final salt = body['salt'];
    if (salt is! String) return null;
    final legacyRecovery = body['legacyRecovery'];
    return (
      salt: base64Decode(salt),
      legacy: body['legacy'] == true,
      legacyRecovery: legacyRecovery is bool ? legacyRecovery : null,
    );
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
  /// [password] is the account's password, which the Quark checks before
  /// deleting anything, so holding a session is not on its own consent to
  /// delete the account (#2346).
  static Future<DeleteAccountResult> deleteAccount({
    required String password,
  }) => _deleteAspects(
    password: password,
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
  ///
  /// [password] gates it the same way it gates [deleteAccount].
  static Future<DeleteAccountResult> resetQuark({
    required String password,
    required bool database,
    required bool files,
    required bool devices,
  }) => _deleteAspects(
    password: password,
    aspects: {
      'database': database.toString(),
      'files': files.toString(),
      'devices': devices.toString(),
    },
    context: 'Quark reset failed',
  );

  /// Issues the delete with [aspects] selected, and forgets the local session.
  ///
  /// [password], or the auth key that stands in for it ([AuthSecret]), travels
  /// in the JSON body, never the URL: query strings end up in access and
  /// proxy logs.
  ///
  /// The Quark revokes the session either way, so the token is dropped on
  /// success and the caller routes the user out. Failure keeps it: nothing was
  /// destroyed and the session still works.
  static Future<DeleteAccountResult> _deleteAspects({
    required String password,
    required Map<String, String> aspects,
    required String context,
  }) async {
    final token = AppSettings.instance.sessionToken;
    if (token == null) throw const UnauthorizedException();
    // A session that predates the app recording its username asks the Quark.
    final username =
        AppSettings.instance.username ?? (await checkStatus()).username;
    if (username == null) throw const UnauthorizedException();
    final secret = await AuthSecret.resolve(
      username: username,
      password: password,
      use: AuthSecretUse.reconfirm,
    );
    final uri = _baseUri
        .resolve('/api/v0/auth/account')
        .replace(queryParameters: aspects);
    final response = await authHttpClientFactory()
        .delete(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'password': secret.confirmation}),
        )
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
    // The last active admin cannot delete their account while anyone else
    // still has one (#1909). The Quark refuses with 409 and deletes nothing,
    // so the session stays.
    if (response.statusCode == 409) {
      throw const MessageException(Errors.lastAdmin);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = _tryDecodeError(response.body);
      // A wrong password is a 403 like a member asking for a reset, so the
      // Quark's error text is what tells them apart (ErrIncorrectPassword in
      // authutil). Nothing was deleted and the session stays.
      if (response.statusCode == 403 && body == 'incorrect password') {
        throw const MessageException(Errors.incorrectPassword);
      }
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

  /// Throws for a sign-in the Quark refused because of the account's status
  /// rather than its password: a 403 whose `status` is `pending` or
  /// `disabled` (#1908). Mapped by that field, not by the text beside it. Any
  /// other 403 passes on the Quark's own text.
  static Never _throwAccountRefusal(String body, String context) {
    Object? status;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) status = decoded['status'];
    } on FormatException {
      status = null;
    }
    switch (status) {
      case 'pending':
        throw const MessageException(Errors.accountPending);
      case 'disabled':
        throw const MessageException(Errors.accountDisabled);
    }
    throwApiError(403, _tryDecodeError(body), context);
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
