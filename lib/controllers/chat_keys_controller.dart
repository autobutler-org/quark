import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:quark/models/chat_keys.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/services/chat_key_service.dart';
import 'package:quark/utils/error_text.dart';

/// Holds the signed-in account's unlocked chat identity for the whole app
/// (#2416).
///
/// The identity's private seeds leave the client only wrapped: under Argon2id
/// of the login password, and of the recovery phrase when one was to hand.
/// [signedIn] runs at every sign-in with the password the form already has:
/// it unwraps the stored identity, or makes and uploads one when there is
/// none. [keysForRecovery] opens it with the phrase and re-wraps it under the
/// new password for `/auth/recover`.
///
/// On native the unwrapped seeds are cached in the platform keystore so a
/// restart stays unlocked; on web they live only in memory, so after a reload
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
      required String recoveryPhrase,
    })?
    fetchForRecovery,
    Future<String?> Function(String key)? readCache,
    Future<void> Function(String key, String value)? writeCache,
    Future<void> Function(String key)? deleteCache,
    String? Function()? activeHost,
    bool? persist,
    this.kdfParams = KdfParams.standard,
  }) : _loadCrypto = loadCrypto ?? ChatCrypto.load,
       _fetchMine = fetchMine ?? ChatKeyService.fetchMine,
       _putMine = putMine ?? ChatKeyService.putMine,
       _fetchForRecovery =
           fetchForRecovery ?? AuthService.fetchRecoveryChatKeys,
       _readCache = readCache ?? _secureRead,
       _writeCache = writeCache ?? _secureWrite,
       _deleteCache = deleteCache ?? _secureDelete,
       _activeHost = activeHost ?? (() => AppSettings.instance.activeHost),
       _persist = persist ?? !kIsWeb;

  /// The app's controller.
  static final ChatKeysController instance = ChatKeysController();

  final Future<ChatCrypto> Function() _loadCrypto;
  final Future<WrappedChatKeys?> Function({String? sessionToken}) _fetchMine;
  final Future<void> Function(WrappedChatKeys keys, {String? sessionToken})
  _putMine;
  final Future<WrappedChatKeys?> Function({
    required String username,
    required String recoveryPhrase,
  })
  _fetchForRecovery;
  final Future<String?> Function(String key) _readCache;
  final Future<void> Function(String key, String value) _writeCache;
  final Future<void> Function(String key) _deleteCache;
  final String? Function() _activeHost;
  final bool _persist;

  /// The Argon2id cost new wraps use.
  final KdfParams kdfParams;

  static const _storage = FlutterSecureStorage();
  static Future<String?> _secureRead(String key) => _storage.read(key: key);
  static Future<void> _secureWrite(String key, String value) =>
      _storage.write(key: key, value: value);
  static Future<void> _secureDelete(String key) => _storage.delete(key: key);

  ChatCrypto? _crypto;
  ChatIdentity? _identity;
  String? _identityHost;

  /// The unlocked identity, or null while locked.
  ChatIdentity? get identity => _identity;

  /// Whether chat can read and write: false on web after a reload until
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
  Future<void> unlock(String password) => signedIn(password: password);

  /// Runs at every sign-in, with the password the form had.
  ///
  /// Unwraps the stored identity, or makes, wraps and uploads a new one when
  /// the account has none. [recoveryPhrase] is present at a first sign-in and
  /// adds the phrase wrap that later recovery opens; keys made without it
  /// can't survive a recovery. [sessionToken] is for a session the app has
  /// not stored yet.
  Future<void> signedIn({
    required String password,
    String? recoveryPhrase,
    String? sessionToken,
  }) async {
    final crypto = await _cryptoLoaded();
    final stored = await _fetchMine(sessionToken: sessionToken);
    final ChatIdentity identity;
    if (stored == null) {
      identity = crypto.generateIdentity();
      await _putMine(
        _wrapAll(crypto, identity, password, recoveryPhrase),
        sessionToken: sessionToken,
      );
    } else {
      identity = crypto.unwrap(stored.byPassword, password, stored.kdfParams);
    }
    await _adopt(identity);
  }

  /// Recovery's half of the work, before `/auth/recover` resets the password:
  /// fetches the identity with [recoveryPhrase], opens it, and returns it
  /// re-wrapped under [newPassword] and the phrase, to send in that request.
  ///
  /// An account with no keys, or keys made without a phrase wrap, gets a new
  /// identity, since nothing else can open the old one; its old messages stay
  /// sealed. A wrong phrase throws what the Quark said.
  Future<WrappedChatKeys> keysForRecovery({
    required String username,
    required String recoveryPhrase,
    required String newPassword,
  }) async {
    final crypto = await _cryptoLoaded();
    final phrase = normalizeRecoveryPhrase(recoveryPhrase);
    final stored = await _fetchForRecovery(
      username: username,
      recoveryPhrase: recoveryPhrase,
    );
    final byPhrase = stored?.byPhrase;
    final identity = stored == null || byPhrase == null
        ? crypto.generateIdentity()
        : crypto.unwrap(
            byPhrase,
            phrase,
            stored.kdfParams,
            wrongSecret: Errors.chatKeysWrongPhrase,
          );
    try {
      return _wrapAll(crypto, identity, newPassword, phrase);
    } finally {
      identity.dispose();
    }
  }

  /// Forgets the unlocked identity and, when [forget], the native cache for
  /// the active Quark.
  Future<void> lock({bool forget = false}) async {
    final host = _identityHost ?? _activeHost();
    _setIdentity(null, null);
    if (forget && _persist && host != null) await _deleteCache(_cacheKey(host));
  }

  /// The phrase as the Quark checks it: trimmed and lowercased, as
  /// `authutil.NormalizeRecoveryPhrase` does, so a phrase typed with capitals
  /// still opens its wrap.
  static String normalizeRecoveryPhrase(String phrase) =>
      phrase.trim().toLowerCase();

  WrappedChatKeys _wrapAll(
    ChatCrypto crypto,
    ChatIdentity identity,
    String password,
    String? recoveryPhrase,
  ) => WrappedChatKeys(
    publicKeys: identity.publicKeys,
    byPassword: crypto.wrap(identity, password, kdfParams),
    byPhrase: recoveryPhrase == null
        ? null
        : crypto.wrap(
            identity,
            normalizeRecoveryPhrase(recoveryPhrase),
            kdfParams,
          ),
    kdfParams: kdfParams,
  );

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
