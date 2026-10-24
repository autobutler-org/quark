import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:quark/controllers/chat_keys_controller.dart';
import 'package:quark/models/account_keys.dart';
import 'package:quark/models/chat_keys.dart';
import 'package:quark/models/vault_key.dart';
import 'package:quark/services/account_crypto.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_secret.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/feature_flags_service.dart';
import 'package:quark/services/settings_service.dart';
import 'package:quark/services/vault_service.dart';
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
  /// generated it and sent the Quark only its recovery key (#2430).
  final String recoveryPhrase;

  const SetupResult({required this.sessionToken, required this.recoveryPhrase});
}

/// Result of [AuthService.login] and [AuthService.recover].
class LoginResult {
  final String sessionToken;

  /// The account the session is for.
  final String username;

  /// A recovery phrase to show the user once, from [AuthService.login]: the
  /// phrase the app just gave an account that had no recovery key, such as
  /// one an admin created (#1873, #2430). Non-null means the session has not
  /// been stored yet: the caller shows the phrase, then calls
  /// [AuthService.acceptSession] once it has been acknowledged.
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
/// [sessionToken] is the new session, which the app may not have stored yet.
/// [authSalt] is the salt the sign-in's auth key was derived with (#2430).
/// [phraseWrapKey] is the wrap key of a phrase the app generated, and the
/// result is the keys re-wrapped under it; see [ChatKeysController.signedIn].
Future<WrappedChatKeys?> Function({
  required String password,
  SecureKey? phraseWrapKey,
  required String sessionToken,
  Uint8List? authSalt,
})
chatKeysOnSignIn =
    ({required password, phraseWrapKey, required sessionToken, authSalt}) =>
        ChatKeysController.instance.signedIn(
          password: password,
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
  required Uint8List authSalt,
})
chatKeysForRecovery = ChatKeysController.instance.keysForRecovery;

/// Opens the account's chat keys with the current password and re-wraps them
/// under the new one, for [AuthService.changePassword] to send (#3022). See
/// [ChatKeysController.keysForPasswordChange]. Overridable in tests.
Future<WrappedChatKeys?> Function({
  required String currentPassword,
  required String newPassword,
  required Uint8List authSalt,
})
chatKeysForPasswordChange = ChatKeysController.instance.keysForPasswordChange;

/// The signed-in account's wrapped vault key, or null when it has no vault,
/// for [AuthService.changePassword] and a recovery phrase rotation to
/// re-wrap (#3461). [sessionToken] is for a session the app has not stored
/// yet. Overridable in tests.
Future<WrappedVaultKey?> Function({String? sessionToken}) vaultKeyFetch =
    VaultService.fetchKey;

/// [username]'s wrapped vault key for a recovery, which has no session, or
/// null when the account has no vault (#3461). See
/// [AuthService.fetchRecoveryVaultKey]. Overridable in tests.
Future<WrappedVaultKey?> Function({
  required String username,
  String? recoveryPhrase,
  String? recoveryKey,
})
recoveryVaultKeyFetch = AuthService.fetchRecoveryVaultKey;

/// Opens the vault key [wrapped] with [keys]' `vaultWrapKey`, or null when it
/// does not open. Disposes [keys] unless [keep].
SecureKey? _openVaultKey(
  AccountCrypto crypto,
  WrappedSecret wrapped,
  AuthKeys keys, {
  bool keep = false,
}) {
  try {
    return crypto.unwrapVaultKey(
      wrapped,
      keys.vaultWrapKey,
      wrongSecret: 'the vault key does not open',
    );
  } on MessageException {
    return null;
  } finally {
    if (!keep) keys.dispose();
  }
}

/// [vaultKey] wrapped afresh at [KdfParams.standard]: under [password]'s
/// `vaultWrapKey` over [authSalt], and under [phrase]'s when there is one.
WrappedVaultKey _wrapVaultKey(
  AccountCrypto crypto,
  SecureKey vaultKey, {
  required String password,
  required AuthKeys? phrase,
  required Uint8List authSalt,
}) {
  const params = KdfParams.standard;
  final keys = crypto.deriveAuthKeys(password, authSalt, params);
  try {
    return WrappedVaultKey(
      byPassword: crypto.wrapVaultKey(vaultKey, keys.vaultWrapKey, authSalt),
      byPhrase: phrase == null
          ? null
          : crypto.wrapVaultKey(vaultKey, phrase.vaultWrapKey, authSalt),
      kdfParams: phrase == null ? params.split : params.phraseSplit,
    );
  } finally {
    keys.dispose();
  }
}

/// The vault key re-wrapped for `PUT /auth/password` (#3461): opened with
/// [currentPassword] and wrapped under [newPassword] over [authSalt], the
/// phrase wrap kept as stored, since the phrase has not changed, and with it
/// the Argon2id cost it records, raised to [KdfParams.standard] where it is
/// below it (#3648). Null for an account with no vault, and for
/// one whose key [currentPassword] does not open, which then stays wrapped
/// under the password it was made with.
Future<WrappedVaultKey?> _vaultKeyForPasswordChange({
  required String currentPassword,
  required String newPassword,
  required Uint8List authSalt,
}) async {
  final stored = await vaultKeyFetch();
  if (stored == null) return null;
  final crypto = await AccountCrypto.load();
  final params = stored.kdfParams;
  final vaultKey = _openVaultKey(
    crypto,
    stored.byPassword,
    crypto.deriveAuthKeys(currentPassword, stored.byPassword.salt, params),
  );
  if (vaultKey == null) return null;
  try {
    final next = params.atLeast(KdfParams.standard);
    final keys = crypto.deriveAuthKeys(newPassword, authSalt, next);
    try {
      return WrappedVaultKey(
        byPassword: crypto.wrapVaultKey(vaultKey, keys.vaultWrapKey, authSalt),
        byPhrase: stored.byPhrase,
        kdfParams: next,
      );
    } finally {
      keys.dispose();
    }
  } finally {
    vaultKey.dispose();
  }
}

/// The vault key re-wrapped for `POST /auth/recover` (#3461): fetched with
/// the same credential as the chat keys, opened with the phrase wrap, and
/// wrapped under [newPassword] and the phrase the account keeps
/// ([newPhraseKeys], else [recoveryKeys]).
///
/// [recoveryKeys] open the phrase wrap when given; without them, for an
/// account with no recovery key yet, the phrase derives its own. Null for an
/// account with no vault, and for one whose key has no phrase wrap or the
/// phrase does not open: nothing the user still holds opens that vault, and
/// there is no admin recovery, so it stays under the lost password until it
/// is deleted from the vault page.
Future<WrappedVaultKey?> _vaultKeyForRecovery({
  required String username,
  required String recoveryPhrase,
  required AuthKeys? recoveryKeys,
  required AuthKeys? newPhraseKeys,
  required String newPassword,
  required Uint8List authSalt,
}) async {
  final stored = await recoveryVaultKeyFetch(
    username: username,
    recoveryPhrase: recoveryKeys == null ? recoveryPhrase : null,
    recoveryKey: recoveryKeys?.authKey,
  );
  final byPhrase = stored?.byPhrase;
  if (stored == null || byPhrase == null) return null;
  final crypto = await AccountCrypto.load();
  final vaultKey = _openVaultKey(
    crypto,
    byPhrase,
    recoveryKeys ??
        crypto.deriveRecoveryKeys(
          recoveryPhrase,
          byPhrase.salt,
          stored.kdfParams,
        ),
    keep: recoveryKeys != null,
  );
  if (vaultKey == null) return null;
  try {
    return _wrapVaultKey(
      crypto,
      vaultKey,
      password: newPassword,
      phrase: newPhraseKeys ?? recoveryKeys,
      authSalt: authSalt,
    );
  } finally {
    vaultKey.dispose();
  }
}

/// The vault key re-wrapped for `PUT /auth/recovery-key` (#3461): opened
/// with [password], the sign-in's, and wrapped under it and [phraseKeys], the
/// new phrase's. This is how a vault made with no phrase wrap gets one. Null
/// for an account with no vault, and for one whose key [password] does not
/// open, which keeps the wraps it has.
Future<WrappedVaultKey?> _vaultKeyForNewPhrase({
  required String password,
  required AuthKeys phraseKeys,
  required String sessionToken,
  required Uint8List authSalt,
}) async {
  final stored = await vaultKeyFetch(sessionToken: sessionToken);
  if (stored == null) return null;
  final crypto = await AccountCrypto.load();
  final vaultKey = _openVaultKey(
    crypto,
    stored.byPassword,
    crypto.deriveAuthKeys(password, stored.byPassword.salt, stored.kdfParams),
  );
  if (vaultKey == null) return null;
  try {
    return _wrapVaultKey(
      crypto,
      vaultKey,
      password: password,
      phrase: phraseKeys,
      authSalt: authSalt,
    );
  } finally {
    vaultKey.dispose();
  }
}

/// Runs [chatKeysOnSignIn] without holding up the sign-in. Chat is not what
/// the user signed in for, and chat unlocks later from its own prompt when
/// this fails. [recovery] is the keys of a phrase the app generated, used for
/// the phrase wrap and disposed once the unlock is done.
void _unlockChatKeys({
  required String password,
  AuthKeys? recovery,
  required String sessionToken,
  required Uint8List authSalt,
}) {
  unawaited(
    Future(
          () => chatKeysOnSignIn(
            password: password,
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
    final token = AppSettings.instance.bearerToken;
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

  /// The [refreshAccount] still running, if there is one.
  ///
  /// The events socket's first open can land while the start-up refresh is
  /// in flight. That open is not a reconnect, so it waits and sees whether
  /// the refresh failed before trying again (#3465).
  static Future<void>? _accountRefresh;

  /// What the last [refreshAccount] for a signed-in session threw, null when
  /// it succeeded.
  ///
  /// A failed call keeps the previous [AppSettings.isAdmin], which is false
  /// on launch. The first socket open retries once when this is set.
  static Object? _accountRefreshError;

  /// Waits out the [refreshAccount] in flight, if there is one, and answers
  /// what the last one threw, or null when [AppSettings.isAdmin] is the
  /// Quark's answer.
  ///
  /// Files waits on this before its first listing, so an admin is not listed
  /// their home and then the root (#3211). Never waits when nothing is in
  /// flight; the caller bounds the wait.
  static Future<Object?> accountSettled() async {
    final inFlight = _accountRefresh;
    if (inFlight != null) await inFlight;
    return _accountRefreshError;
  }

  /// Whether the events socket has opened once since [watchAccount].
  ///
  /// Later opens are reconnects and refresh on their own (#3209).
  static bool _openedAccountSocket = false;

  static final List<StreamSubscription<dynamic>> _accountWatchSubscriptions =
      [];

  /// Fetches the signed-in user's admin flag again into [AppSettings.isAdmin],
  /// their id and picture version into [AppSettings.userId] and
  /// [AppSettings.avatarUpdatedAt], the beta feature flags into
  /// [AppSettings.featureFlags], and the Quark's theme color and the user's own
  /// into [AppSettings.themeColor] (#2740). The Quark's theme color needs no session,
  /// so it is fetched for the sign-in page too.
  ///
  /// Without a session there is no admin and no account. A failed call keeps
  /// the last known value: it only decides what the app shows, and the Quark
  /// still refuses admin-only requests from a non-admin. [watchAccount] asks
  /// again on the events socket's first open when this fails, so a start-up
  /// miss does not leave [AppSettings.isAdmin] false for the session (#3465).
  static Future<void> refreshAccount() {
    final run = _refreshAccount();
    _accountRefresh = run;
    return run.whenComplete(() {
      if (identical(_accountRefresh, run)) _accountRefresh = null;
    });
  }

  static Future<void> _refreshAccount() async {
    final settings = AppSettings.instance;
    unawaited(SettingsService.refreshThemeColor());
    if (settings.sessionToken == null) {
      settings.isAdmin.value = false;
      settings.userId.value = null;
      settings.avatarUpdatedAt.value = null;
      settings.featureFlags.value = const [];
      _accountRefreshError = null;
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
      _accountRefreshError = null;
    } catch (e) {
      _accountRefreshError = e;
      debugPrint('[auth_service.dart] refreshAccount failed: $e');
    }
  }

  /// Keeps [AppSettings.isAdmin] current for the life of the app.
  ///
  /// Refreshes now, whenever the session changes (sign-in, sign-out, a 401,
  /// switching Quarks), and whenever the Quark reports an account's role
  /// changed, so a demoted admin loses admin-only entries without signing out.
  /// The Quark closes the socket of the account whose role changed instead of
  /// sending it that event, so every reconnect refreshes too. The first
  /// connection does not refresh on its own: the refresh below already covers
  /// a successful start, and following the open as well asked the Quark
  /// everything twice on every load (#3209). A failed start-up refresh is the
  /// exception. The first open, which is not a reconnect, tries it once more
  /// (#3465).
  static void watchAccount() {
    stopWatchingAccount();
    AppSettings.instance.sessionTokenNotifier.addListener(refreshAccount);
    // Switching between two Quarks that are both signed out moves no session,
    // and the sign-in page still wants the new Quark's theme color (#2740).
    AppSettings.instance.activeHostNotifier.addListener(
      SettingsService.refreshThemeColor,
    );
    _accountWatchSubscriptions.add(
      EventsService.instance.events.listen(_onAccountEvent),
    );
    // Subscribed before [EventsService.start], so the first open is not missed.
    _accountWatchSubscriptions.add(
      EventsService.instance.connections.listen(
        (_) => _onAccountSocketOpened(),
      ),
    );
    _accountWatchSubscriptions.add(
      EventsService.instance.reconnects.listen((_) => refreshAccount()),
    );
    EventsService.instance.start();
    refreshAccount();
  }

  /// Drops the listeners [watchAccount] installed.
  ///
  /// [watchAccount] calls this first, so a later call replaces those listeners
  /// instead of stacking a second copy. Safe when nothing is watching.
  @visibleForTesting
  static void stopWatchingAccount() {
    AppSettings.instance.sessionTokenNotifier.removeListener(refreshAccount);
    AppSettings.instance.activeHostNotifier.removeListener(
      SettingsService.refreshThemeColor,
    );
    for (final subscription in _accountWatchSubscriptions) {
      subscription.cancel();
    }
    _accountWatchSubscriptions.clear();
    _accountRefresh = null;
    _accountRefreshError = null;
    _openedAccountSocket = false;
  }

  static void _onAccountEvent(FileEvent event) {
    if (event.kind == 'account_changed') refreshAccount();
    // An admin flipped a beta on or off; members follow it live (#2542).
    if (event.kind == 'feature_flag_changed') FeatureFlagsService.refresh();
    // An admin changed the Quark's default theme color (#2740).
    if (event.kind == 'public_settings_changed') {
      SettingsService.refreshThemeColor();
    }
  }

  /// Retries a failed start-up [refreshAccount] on the socket's first open.
  ///
  /// The open often lands before that call has heard back. Waiting for it
  /// keeps a successful start to one load (#3209) and still recovers when it
  /// failed (#3465). A later open is a reconnect and refreshes on its own,
  /// including when this one retry also failed.
  static void _onAccountSocketOpened() {
    if (_openedAccountSocket) return;
    _openedAccountSocket = true;
    unawaited(_retryAccountRefreshIfFailed());
  }

  static Future<void> _retryAccountRefreshIfFailed() async {
    final inFlight = _accountRefresh;
    if (inFlight != null) await inFlight;
    if (_accountRefreshError == null) return;
    _accountRefreshError = null;
    await refreshAccount();
  }

  /// Creates the owner account on first boot.
  /// Returns a [SetupResult] containing the session token and the recovery
  /// phrase the app generated, which is shown exactly once — the caller must
  /// surface it.
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
    final mine = await _newRecoveryPhrase(secret.salt);
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
      mine.keys.dispose();
      rethrow;
    }
    final token = body['token'] as String;
    await AppSettings.instance.setSessionToken(token);
    await AppSettings.instance.setUsername(username);
    _unlockChatKeys(
      password: password,
      recovery: mine.keys,
      sessionToken: token,
      authSalt: secret.salt,
    );
    return SetupResult(sessionToken: token, recoveryPhrase: mine.phrase);
  }

  /// Authenticates with username and password, returns a session token.
  ///
  /// The Quark is sent an auth key derived from [password] (#2430). The
  /// password goes beside it only once, to move an account the Quark marks
  /// `legacy` to the key; see [AuthSecret] for that and for the Quarks and
  /// accounts that are refused instead.
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
          body: jsonEncode({
            'username': username,
            'password': ?secret.password,
            'authKey': secret.authKey,
          }),
        )
        .timeout(kAuthRequestTimeout);
    if (response.statusCode == 401) {
      throw const MessageException(Errors.invalidCredentials);
    }
    if (response.statusCode == 403) {
      _throwAccountRefusal(response.body, 'Login failed');
    }
    throwUnlessOk(response, 'Login failed', orMessage: true);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['token'] as String;
    final String? phrase;
    // An account with no recovery key, such as one an admin created, is
    // given a phrase the app makes (#2430). That waits for the chat keys,
    // which have to be wrapped under it; any other sign-in leaves them to
    // finish on their own.
    if (body['legacyRecovery'] == true) {
      phrase = await _rotateRecoveryPhrase(
        password: password,
        secret: secret,
        sessionToken: token,
      );
    } else {
      phrase = null;
      _unlockChatKeys(
        password: password,
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

  /// Gives the account a recovery phrase the app generated, for one that has
  /// no recovery key (#2430), and returns it, or null when that failed.
  ///
  /// Unlocks the chat keys first, since their phrase wrap has to move to the
  /// new phrase, then registers the phrase's recovery key with
  /// `PUT /auth/recovery-key`, which stores the re-wrapped keys in the same
  /// transaction, as it does the vault key, opened with the password and
  /// wrapped under both (#3461). The phrase is returned only once the Quark
  /// answers 204;
  /// until then the account has none. A failure is logged and nothing else:
  /// the sign-in stands, and the next one tries again. So does one whose chat
  /// keys would not open, since only they can be re-wrapped.
  static Future<String?> _rotateRecoveryPhrase({
    required String password,
    required AuthSecret secret,
    required String sessionToken,
  }) async {
    final NewRecoveryPhrase mine;
    try {
      mine = await _newRecoveryPhrase(secret.salt);
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
      final vaultKey = await _vaultKeyForNewPhrase(
        password: password,
        phraseKeys: mine.keys,
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
              'vaultKey': ?vaultKey?.toJson(),
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
  /// password changes. The vault key is carried over the same way when its
  /// phrase wrap opens (#3461); a vault with no phrase wrap stays under the
  /// lost password, since nothing else opens it.
  ///
  /// The Quark is sent the new password's auth key, never the password
  /// (#2430). What stands in for the phrase follows `GET /auth/salt`. An
  /// account with a recovery key is sent the key derived from
  /// [recoveryPhrase], never the phrase. One without (`legacyRecovery`) can
  /// only be checked by the phrase, so it is sent once, beside the recovery
  /// key of a new phrase the app generates, and the result's
  /// [LoginResult.recoveryPhrase] carries that phrase to show. The app
  /// believes a `legacyRecovery` answer every time, so a compromised Quark can
  /// collect the phrase this way (docs/chat-security.md).
  static Future<LoginResult> recover({
    required String username,
    required String recoveryPhrase,
    required String newPassword,
  }) async {
    // The salt asked for now is the one the Quark keeps with the new key.
    final secret = await AuthSecret.resolve(
      username: username,
      password: newPassword,
      use: AuthSecretUse.newCredential,
    );
    final legacy = secret.legacyRecovery;
    final crypto = await ChatCrypto.load();
    final typed = legacy
        ? null
        : crypto.deriveRecoveryKeys(
            recoveryPhrase,
            secret.salt,
            KdfParams.standard,
          );
    NewRecoveryPhrase? next;
    final http.Response response;
    try {
      next = legacy ? await _newRecoveryPhrase(secret.salt) : null;
      final chatKeys = await chatKeysForRecovery(
        username: username,
        recoveryPhrase: recoveryPhrase,
        recoveryKeys: typed,
        newPhraseWrapKey: next?.keys.wrapKey,
        newPassword: newPassword,
        authSalt: secret.salt,
      );
      final vaultKey = await _vaultKeyForRecovery(
        username: username,
        recoveryPhrase: recoveryPhrase,
        recoveryKeys: typed,
        newPhraseKeys: next?.keys,
        newPassword: newPassword,
        authSalt: secret.salt,
      );
      response = await authHttpClientFactory()
          .post(
            _baseUri.resolve('/api/v0/auth/recover'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username,
              if (typed != null)
                'recoveryKey': typed.authKey
              else
                'recoveryPhrase': recoveryPhrase,
              'newAuthKey': secret.authKey,
              'newRecoveryKey': ?next?.keys.authKey,
              'chatKeys': chatKeys.toJson(),
              'vaultKey': ?vaultKey?.toJson(),
            }),
          )
          .timeout(kAuthRequestTimeout);
    } finally {
      typed?.dispose();
      next?.keys.dispose();
    }
    // A pending or disabled account is refused like a sign-in (#1908).
    if (response.statusCode == 403) {
      _throwAccountRefusal(response.body, 'Recovery failed');
    }
    throwUnlessOk(response, 'Recovery failed', orMessage: true);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['token'] as String;
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
  /// (#2416). The Quark checks the credential first, as `/auth/recover` does,
  /// and changes nothing. Exactly one of [recoveryKey], the key derived from
  /// the phrase, and [recoveryPhrase], for an account with no recovery key
  /// yet, is sent (#2430). Null when the account has no chat keys.
  ///
  /// A wrong phrase throws the Quark's own text; a pending or disabled
  /// account is refused as a sign-in is.
  static Future<WrappedChatKeys?> fetchRecoveryChatKeys({
    required String username,
    String? recoveryPhrase,
    String? recoveryKey,
  }) async {
    final json = await _postRecoveryCheck(
      '/api/v0/auth/recover/keys',
      username: username,
      recoveryPhrase: recoveryPhrase,
      recoveryKey: recoveryKey,
    );
    return json == null ? null : WrappedChatKeys.fromJson(json);
  }

  /// [username]'s wrapped vault key, for recovery (#3461): the vault's half
  /// of [fetchRecoveryChatKeys], checked and answered the same way. Null when
  /// the account has no vault.
  static Future<WrappedVaultKey?> fetchRecoveryVaultKey({
    required String username,
    String? recoveryPhrase,
    String? recoveryKey,
  }) async {
    final json = await _postRecoveryCheck(
      '/api/v0/auth/recover/vault-key',
      username: username,
      recoveryPhrase: recoveryPhrase,
      recoveryKey: recoveryKey,
    );
    return json == null ? null : WrappedVaultKey.fromJson(json);
  }

  /// Posts a recovery credential to [path], which checks it as
  /// `/auth/recover` does and changes nothing, and returns the 2xx body, or
  /// null for a 404.
  static Future<Map<String, dynamic>?> _postRecoveryCheck(
    String path, {
    required String username,
    String? recoveryPhrase,
    String? recoveryKey,
  }) async {
    final uri = _baseUri.resolve(path);
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
    throwUnlessOk(response, 'Recovery failed', orMessage: true);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Asks this Quark for an account (#1908) and returns the new account's
  /// recovery phrase, which is shown once. The app generates it and sends
  /// only its recovery key (#2430).
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
    final mine = await _newRecoveryPhrase(secret.salt);
    try {
      await _postNewAccount(
        uri,
        username: username,
        secret: secret,
        mine: mine,
        context: 'Account request failed',
        notFound: Errors.accessRequestsOff,
      );
      return mine.phrase;
    } finally {
      // The account's chat keys are made at its first sign-in, which has no
      // phrase to wrap them under.
      mine.keys.dispose();
    }
  }

  /// Posts a new account's credentials to [uri] and returns the 2xx body:
  /// [secret]'s auth key and [mine]'s recovery key. A 404 throws [notFound]
  /// when it is set.
  static Future<Map<String, dynamic>> _postNewAccount(
    Uri uri, {
    required String username,
    required AuthSecret secret,
    required NewRecoveryPhrase mine,
    required String context,
    String? notFound,
  }) async {
    final response = await authHttpClientFactory()
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': username,
            'authKey': secret.authKey,
            'recoveryKey': mine.keys.authKey,
          }),
        )
        .timeout(kAuthRequestTimeout);
    if (response.statusCode == 404 && notFound != null) {
      throw MessageException(notFound);
    }
    throwUnlessOk(response, context, orMessage: true);
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

  /// Changes the signed-in account's password from [currentPassword] to
  /// [newPassword] with `PUT /auth/password` (#3022). The session stays.
  ///
  /// The Quark is sent the two passwords' auth keys, never the passwords
  /// (#2430): the current one's re-confirms the caller, as it does for
  /// [deleteAccount]. The account's chat keys are opened with
  /// [currentPassword] first and sent re-wrapped under [newPassword] in the
  /// same request, so chat history survives the change, and so is the vault
  /// key (#3461). A current password that opens no chat keys fails here,
  /// before anything is sent; a vault key it does not open is left out and
  /// stays under the password it was made with.
  ///
  /// A wrong current password throws [Errors.wrongCurrentPassword], and
  /// nothing changed.
  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final session = await _sessionAccount();
    final current = await AuthSecret.resolve(
      username: session.username,
      password: currentPassword,
      use: AuthSecretUse.reconfirm,
    );
    // ponytail: asks for the salt a second time rather than teaching
    // AuthSecret to derive two keys from one answer.
    final next = await AuthSecret.resolve(
      username: session.username,
      password: newPassword,
      use: AuthSecretUse.newCredential,
    );
    final chatKeys = await chatKeysForPasswordChange(
      currentPassword: currentPassword,
      newPassword: newPassword,
      authSalt: next.salt,
    );
    final vaultKey = await _vaultKeyForPasswordChange(
      currentPassword: currentPassword,
      newPassword: newPassword,
      authSalt: next.salt,
    );
    final response = await authHttpClientFactory()
        .put(
          _baseUri.resolve('/api/v0/auth/password'),
          headers: {
            'Authorization': ?session.authorization,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            // The re-confirmation takes the auth key, never the password.
            'password': current.authKey,
            'newAuthKey': next.authKey,
            'chatKeys': ?chatKeys?.toJson(),
            'vaultKey': ?vaultKey?.toJson(),
          }),
        )
        .timeout(kAuthRequestTimeout);
    if (response.statusCode == 401) throw const UnauthorizedException();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = serverErrorText(response.body, orMessage: true);
      // ErrIncorrectPassword in authutil, as [_deleteAspects] reads it.
      if (response.statusCode == 403 && body == 'incorrect password') {
        throw const MessageException(Errors.wrongCurrentPassword);
      }
      // The status alone: the Quark's text for a refused key is not copy.
      throw ApiException(response.statusCode, 'Password change failed');
    }
  }

  /// The `Authorization` header value for the stored session, null when the
  /// request carries none: signed out, or a cookie session.
  static String? get _authorization {
    final token = AppSettings.instance.bearerToken;
    return token == null ? null : 'Bearer $token';
  }

  /// The stored session's `Authorization` header value (null for a cookie
  /// session) and the account it is for, which a request that re-confirms the
  /// password needs. Throws [UnauthorizedException] when signed out or the
  /// account is unknown.
  static Future<({String? authorization, String username})>
  _sessionAccount() async {
    if (AppSettings.instance.sessionToken == null) {
      throw const UnauthorizedException();
    }
    final authorization = _authorization;
    // A session that predates the app recording its username asks the Quark.
    final username =
        AppSettings.instance.username ?? (await checkStatus()).username;
    if (username == null) throw const UnauthorizedException();
    return (authorization: authorization, username: username);
  }

  /// Logs out — clears the in-memory session token and notifies the server.
  ///
  /// A cookie session has no token to send, and the request still goes out:
  /// it is what ends the session on the Quark and clears the cookie.
  static Future<void> logout() async {
    final signedIn = AppSettings.instance.sessionToken != null;
    final authorization = _authorization;
    await AppSettings.instance.setSessionToken(null);
    if (!signedIn) return;
    try {
      final uri = _baseUri.resolve('/api/v0/auth/logout');
      await authHttpClientFactory()
          .post(uri, headers: {'Authorization': ?authorization})
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
  /// The auth key that stands in for [password] ([AuthSecret]) travels in
  /// the JSON body, never the URL: query strings end up in access and proxy
  /// logs.
  ///
  /// The Quark revokes the session either way, so the token is dropped on
  /// success and the caller routes the user out. Failure keeps it: nothing was
  /// destroyed and the session still works.
  static Future<DeleteAccountResult> _deleteAspects({
    required String password,
    required Map<String, String> aspects,
    required String context,
  }) async {
    final (:authorization, :username) = await _sessionAccount();
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
            'Authorization': ?authorization,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'password': secret.authKey}),
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
      final body = serverErrorText(response.body, orMessage: true);
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
    throwApiError(403, serverErrorText(body, orMessage: true), context);
  }
}
