import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:quark/models/account_keys.dart';
import 'package:quark/models/chat_keys.dart';
import 'package:quark/services/account_crypto.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/services/chat_key_service.dart';
import 'package:quark/utils/chat_identity_cache.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/recovery_phrase.dart';
import 'package:sodium/sodium_sumo.dart';

/// Holds the signed-in account's unlocked chat identity for the whole app
/// (#2416).
///
/// The identity's private seeds leave the client only wrapped: under a key
/// derived from the login password, and under one derived from the recovery
/// phrase when one was to hand. The password's key is the `wrapKey` of
/// [ChatCrypto.deriveAuthKeys] (#2430), which the Quark is never sent. The
/// phrase's is the `wrapKey` of [ChatCrypto.deriveRecoveryKeys]. Wraps made
/// before #2430 in the first scheme, Argon2id of the secret itself, still
/// open, and a password wrap moves to the split scheme at the next sign-in.
/// [signedIn] runs at every sign-in with the password the form already has:
/// it unwraps the stored identity, or makes and uploads one when there is
/// none. [keysForRecovery] opens it with the phrase and re-wraps it under the
/// new password for `/auth/recover`.
///
/// The unwrapped seeds are cached so a restart stays unlocked: in the
/// platform keystore on native, and in the tab's `sessionStorage` on the web,
/// so a reload no longer asks for the password (#3257); see
/// `readChatIdentityCache`. Without a cached identity, in a new tab say,
/// [isUnlocked] is false until the page layer asks for the password and calls
/// [unlock]. Either way a sign-out locks it and drops the cache.
///
/// Chat code reads [identity] and runs [crypto]'s helpers with it:
/// `seal`/`openSealed` for key grants, `sign`/`verify`, and
/// `encrypt`/`decrypt` for messages.
class ChatKeysController extends ChangeNotifier {
  /// Builds a controller. Every collaborator has a real default; tests pass
  /// fakes.
  ChatKeysController({
    Future<ChatCrypto> Function()? loadCrypto,
    Future<WrappedChatKeys?> Function({String? sessionToken})? fetchMine,
    Future<void> Function(WrappedChatKeys keys, {String? sessionToken})?
    putMine,
    Future<WrappedChatKeys?> Function({
      required String username,
      String? recoveryPhrase,
      String? recoveryKey,
    })?
    fetchForRecovery,
    Future<String?> Function(String key)? readCache,
    Future<void> Function(String key, String value)? writeCache,
    Future<void> Function(String key)? deleteCache,
    String? Function()? activeHost,
    bool persist = true,
    this.kdfParams = KdfParams.standard,
  }) : _loadCrypto = loadCrypto ?? ChatCrypto.load,
       _fetchMine = fetchMine ?? ChatKeyService.fetchMine,
       _putMine = putMine ?? ChatKeyService.putMine,
       _fetchForRecovery =
           fetchForRecovery ?? AuthService.fetchRecoveryChatKeys,
       _readCache = readCache ?? readChatIdentityCache,
       _writeCache = writeCache ?? writeChatIdentityCache,
       _deleteCache = deleteCache ?? deleteChatIdentityCache,
       _activeHost = activeHost ?? (() => AppSettings.instance.activeHost),
       _persist = persist;

  /// The app's controller.
  static final ChatKeysController instance = ChatKeysController();

  final Future<ChatCrypto> Function() _loadCrypto;
  final Future<WrappedChatKeys?> Function({String? sessionToken}) _fetchMine;
  final Future<void> Function(WrappedChatKeys keys, {String? sessionToken})
  _putMine;
  final Future<WrappedChatKeys?> Function({
    required String username,
    String? recoveryPhrase,
    String? recoveryKey,
  })
  _fetchForRecovery;
  final Future<String?> Function(String key) _readCache;
  final Future<void> Function(String key, String value) _writeCache;
  final Future<void> Function(String key) _deleteCache;
  final String? Function() _activeHost;
  final bool _persist;

  /// The Argon2id cost new wraps use.
  final KdfParams kdfParams;

  ChatCrypto? _crypto;
  ChatIdentity? _identity;
  String? _identityHost;

  /// The unlocked identity, or null while locked.
  ChatIdentity? get identity => _identity;

  /// Whether chat can read and write: false without a cached identity until
  /// [unlock].
  bool get isUnlocked => _identity != null;

  /// libsodium, loaded by the first unlock. Null until then.
  ChatCrypto? get crypto => _crypto;

  /// Restores a cached identity and starts following sign-outs. Call once at
  /// startup, after [AppSettings.load].
  Future<void> start() async {
    AppSettings.instance.sessionTokenNotifier.addListener(_onSessionChanged);
    await _restore();
  }

  /// The password prompt's action: unlocks with [password], or, for an
  /// account that has no keys yet, makes them. A wrong password throws a
  /// [MessageException] carrying [Errors.chatKeysWrongPassword].
  ///
  /// Nothing but the stored keys is fetched: a split-scheme wrap carries the
  /// salt its key is derived with.
  Future<void> unlock(String password) => signedIn(password: password);

  /// Runs at every sign-in, with the password the form had.
  ///
  /// Unwraps the stored identity, or makes, wraps and uploads a new one when
  /// the account has none. Keys made without a phrase wrap can't survive a
  /// recovery. [sessionToken] is for a session the app has not stored yet.
  ///
  /// [authSalt] is the salt the sign-in's auth key was derived with. With it,
  /// new keys are wrapped under the split scheme, and a stored wrap still in
  /// the first scheme is re-wrapped and uploaded once it has opened. Without
  /// it, from the chat prompt's [unlock], the first scheme stays.
  ///
  /// [phraseWrapKey], with [authSalt], is the `wrapKey` of a phrase the app
  /// generated ([ChatCrypto.deriveRecoveryKeys]). New keys are uploaded with
  /// their phrase wrap under it.
  /// Stored keys are not: they come back re-wrapped under it, for the request
  /// that registers the phrase to store, since the phrase the stored wrap is
  /// under still works until then. The result is null without it.
  Future<WrappedChatKeys?> signedIn({
    required String password,
    SecureKey? phraseWrapKey,
    String? sessionToken,
    Uint8List? authSalt,
  }) async {
    final crypto = await _cryptoLoaded();
    final stored = await _fetchMine(sessionToken: sessionToken);
    final ChatIdentity identity;
    var current = stored;
    if (stored == null) {
      identity = crypto.generateIdentity();
      current = _wrapAll(
        crypto,
        identity,
        password,
        authSalt,
        phraseWrapKey: phraseWrapKey,
      );
      await _putMine(current, sessionToken: sessionToken);
    } else {
      identity = _openByPassword(crypto, stored, password);
      if (!stored.kdfParams.isSplit && authSalt != null) {
        // The phrase wrap is kept as it is, so the cost it records has to
        // stay the one it was made with, unless that is below [kdfParams]:
        // never copy a weaker cost than the app's own (#3648).
        final params = stored.kdfParams.split.atLeast(kdfParams);
        current = WrappedChatKeys(
          publicKeys: stored.publicKeys,
          byPassword: _wrapByPassword(
            crypto,
            identity,
            password,
            authSalt,
            params,
          ),
          byPhrase: stored.byPhrase,
          kdfParams: params,
        );
        await _putMine(current, sessionToken: sessionToken);
      }
    }
    final rewrapped = phraseWrapKey == null || authSalt == null
        ? null
        : stored == null
        ? current
        : WrappedChatKeys(
            publicKeys: current!.publicKeys,
            byPassword: current.byPassword,
            byPhrase: crypto.wrapWithKey(identity, phraseWrapKey, authSalt),
            kdfParams: current.kdfParams.phraseSplit,
          );
    await _adopt(identity);
    return rewrapped;
  }

  /// A password change's half of the work, before `PUT /auth/password`
  /// stores the new one (#3022): fetches the stored keys, opens them with
  /// [currentPassword], and returns them re-wrapped under [newPassword] to
  /// send in that request. Null for an account with no keys yet, which has
  /// nothing to carry over.
  ///
  /// [authSalt] is the account's auth salt; the result's password wrap is in
  /// the split scheme under it. The phrase wrap is returned as it was stored,
  /// since the recovery phrase has not changed. The unlocked [identity] is
  /// left alone: the same keys are under the new wrap.
  ///
  /// A wrong [currentPassword] throws a [MessageException] carrying
  /// [Errors.wrongCurrentPassword], before anything is sent.
  Future<WrappedChatKeys?> keysForPasswordChange({
    required String currentPassword,
    required String newPassword,
    required Uint8List authSalt,
  }) async {
    final crypto = await _cryptoLoaded();
    final stored = await _fetchMine();
    if (stored == null) return null;
    final identity = _openByPassword(
      crypto,
      stored,
      currentPassword,
      wrongSecret: Errors.wrongCurrentPassword,
    );
    try {
      // The phrase wrap is kept as it is, so the cost it records has to stay
      // the one it was made with, unless that is below [kdfParams]: never
      // copy a weaker cost than the app's own (#3648).
      final params =
          (stored.kdfParams.isSplit ? stored.kdfParams : stored.kdfParams.split)
              .atLeast(kdfParams);
      return WrappedChatKeys(
        publicKeys: stored.publicKeys,
        byPassword: _wrapByPassword(
          crypto,
          identity,
          newPassword,
          authSalt,
          params,
        ),
        byPhrase: stored.byPhrase,
        kdfParams: params,
      );
    } finally {
      identity.dispose();
    }
  }

  /// Adding a recovery phrase's half of the work, before
  /// `PUT /auth/recovery-key` checks the phrase and stores the result (#3530):
  /// fetches the stored keys, opens them with [password], and returns them
  /// wrapped afresh under [password] and [phraseWrapKey], the `wrapKey` of
  /// the account's phrase, both over [authSalt]. Nothing is uploaded here: a
  /// mistyped phrase must never reach the Quark as a wrap, and only that
  /// request checks it. Null for an account with no keys yet. A wrong
  /// password throws a [MessageException] carrying
  /// [Errors.chatKeysWrongPassword].
  Future<WrappedChatKeys?> keysForPhrase({
    required String password,
    required SecureKey phraseWrapKey,
    required Uint8List authSalt,
  }) async {
    final crypto = await _cryptoLoaded();
    final stored = await _fetchMine();
    if (stored == null) return null;
    final identity = _openByPassword(crypto, stored, password);
    try {
      return _wrapAll(
        crypto,
        identity,
        password,
        authSalt,
        phraseWrapKey: phraseWrapKey,
      );
    } finally {
      identity.dispose();
    }
  }

  /// Opens [stored]'s password wrap in whichever scheme it records.
  static ChatIdentity _openByPassword(
    ChatCrypto crypto,
    WrappedChatKeys stored,
    String password, {
    String wrongSecret = Errors.chatKeysWrongPassword,
  }) {
    if (!stored.kdfParams.isSplit) {
      return crypto.unwrap(
        stored.byPassword,
        password,
        stored.kdfParams,
        wrongSecret: wrongSecret,
      );
    }
    final keys = crypto.deriveAuthKeys(
      password,
      stored.byPassword.salt,
      stored.kdfParams,
    );
    try {
      return crypto.unwrapWithKey(
        stored.byPassword,
        keys.wrapKey,
        wrongSecret: wrongSecret,
      );
    } finally {
      keys.dispose();
    }
  }

  /// Recovery's half of the work, before `/auth/recover` resets the password:
  /// fetches the identity, opens it with [recoveryPhrase], and returns it
  /// re-wrapped under [newPassword] and a phrase, to send in that request.
  ///
  /// [authSalt] is the salt the new auth key was derived with (#2430); the
  /// result is in the split scheme under it.
  ///
  /// [recoveryKeys] are [recoveryPhrase]'s keys under [authSalt], for an
  /// account the Quark checks by recovery key: the fetch sends their
  /// `authKey` in place of the phrase, and a phrase-split wrap opens under
  /// their `wrapKey`. Without them, for an account with no recovery key yet,
  /// the raw phrase is sent and a phrase-split wrap derives its own key. An
  /// older phrase wrap opens under Argon2id of the phrase either way. The
  /// result's phrase wrap is under [newPhraseWrapKey], the key of a phrase
  /// this recovery gives the account, else under [recoveryKeys]' `wrapKey`.
  ///
  /// An account with no keys, or keys made without a phrase wrap, gets a new
  /// identity, since nothing else can open the old one; its old messages stay
  /// sealed. A wrong phrase throws what the Quark said.
  Future<WrappedChatKeys> keysForRecovery({
    required String username,
    required String recoveryPhrase,
    AuthKeys? recoveryKeys,
    SecureKey? newPhraseWrapKey,
    required String newPassword,
    required Uint8List authSalt,
  }) async {
    final crypto = await _cryptoLoaded();
    final stored = await _fetchForRecovery(
      username: username,
      recoveryPhrase: recoveryKeys == null ? recoveryPhrase : null,
      recoveryKey: recoveryKeys?.authKey,
    );
    final byPhrase = stored?.byPhrase;
    final identity = stored == null || byPhrase == null
        ? crypto.generateIdentity()
        : _openByPhrase(
            crypto,
            stored.kdfParams,
            byPhrase,
            normalizeRecoveryPhrase(recoveryPhrase),
            recoveryKeys,
          );
    try {
      return _wrapAll(
        crypto,
        identity,
        newPassword,
        authSalt,
        phraseWrapKey: newPhraseWrapKey ?? recoveryKeys?.wrapKey,
      );
    } finally {
      identity.dispose();
    }
  }

  /// Opens a phrase wrap in whichever scheme [params] records.
  static ChatIdentity _openByPhrase(
    ChatCrypto crypto,
    KdfParams params,
    WrappedSecret byPhrase,
    String phrase,
    AuthKeys? recoveryKeys,
  ) {
    if (!params.isPhraseSplit) {
      return crypto.unwrap(
        byPhrase,
        phrase,
        params,
        wrongSecret: Errors.chatKeysWrongPhrase,
      );
    }
    final keys =
        recoveryKeys ??
        crypto.deriveRecoveryKeys(phrase, byPhrase.salt, params);
    try {
      return crypto.unwrapWithKey(
        byPhrase,
        keys.wrapKey,
        wrongSecret: Errors.chatKeysWrongPhrase,
      );
    } finally {
      if (recoveryKeys == null) keys.dispose();
    }
  }

  /// Forgets the unlocked identity and, when [forget], the cache for the
  /// active Quark.
  Future<void> lock({bool forget = false}) async {
    final host = _identityHost ?? _activeHost();
    _setIdentity(null, null);
    if (forget && _persist && host != null) await _deleteCache(_cacheKey(host));
  }

  /// [identity] wrapped under [password] and, when there is one, a phrase:
  /// [phraseWrapKey] with [authSalt].
  WrappedChatKeys _wrapAll(
    ChatCrypto crypto,
    ChatIdentity identity,
    String password,
    Uint8List? authSalt, {
    SecureKey? phraseWrapKey,
  }) {
    final phraseSplit = authSalt != null && phraseWrapKey != null;
    final params = authSalt == null
        ? kdfParams
        : phraseSplit
        ? kdfParams.phraseSplit
        : kdfParams.split;
    return WrappedChatKeys(
      publicKeys: identity.publicKeys,
      byPassword: authSalt == null
          ? crypto.wrap(identity, password, params)
          : _wrapByPassword(crypto, identity, password, authSalt, params),
      byPhrase: phraseSplit
          ? crypto.wrapWithKey(identity, phraseWrapKey, authSalt)
          : null,
      kdfParams: params,
    );
  }

  /// The split scheme's password wrap: under the `wrapKey` derived from
  /// [password] and [authSalt], which is stored as the wrap's salt.
  static WrappedSecret _wrapByPassword(
    ChatCrypto crypto,
    ChatIdentity identity,
    String password,
    Uint8List authSalt,
    KdfParams params,
  ) {
    // ponytail: a second Argon2id run per sign-in, after the one that made the
    // auth key. Pass the wrap key in from AuthSecret if sign-in gets slow.
    final keys = crypto.deriveAuthKeys(password, authSalt, params);
    try {
      return crypto.wrapWithKey(identity, keys.wrapKey, authSalt);
    } finally {
      keys.dispose();
    }
  }

  Future<ChatCrypto> _cryptoLoaded() async => _crypto ??= await _loadCrypto();

  Future<void> _adopt(ChatIdentity identity) async {
    final host = _activeHost();
    _setIdentity(identity, host);
    if (_persist && host != null) {
      await _writeCache(_cacheKey(host), base64Encode(identity.seeds));
    }
  }

  Future<void> _restore() async {
    final host = _activeHost();
    if (!_persist || host == null) return;
    if (AppSettings.instance.sessionToken == null) return;
    final cached = await _readCache(_cacheKey(host));
    if (cached == null) return;
    try {
      final crypto = await _cryptoLoaded();
      // A sign-in that finished while the cache was read wins.
      if (_identity != null) return;
      _setIdentity(crypto.identityFromSeeds(base64Decode(cached)), host);
    } catch (e) {
      debugPrint('[chat_keys_controller.dart] cached identity unreadable: $e');
      await _deleteCache(_cacheKey(host));
    }
  }

  void _onSessionChanged() {
    if (AppSettings.instance.sessionToken == null) {
      lock(forget: true);
    } else if (_identityHost != _activeHost()) {
      // Another Quark, another account.
      _setIdentity(null, null);
      _restore();
    }
  }

  void _setIdentity(ChatIdentity? identity, String? host) {
    if (identical(identity, _identity)) return;
    _identity?.dispose();
    _identity = identity;
    _identityHost = host;
    notifyListeners();
  }

  static String _cacheKey(String host) => 'chat_identity:$host';
}
