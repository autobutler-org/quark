import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/vault_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/native_vault_cache.dart';
import 'package:quark/services/vault_biometric.dart';
import 'package:quark/services/vault_cache.dart';
import 'package:quark/utils/error_text.dart';

/// Unlocking the vault with Face ID, Touch ID or a fingerprint (#3595): the
/// vault page's biometric button, the offer after a password unlock, and the
/// setting that turns it on and off.
///
/// Turned on, the open vault key is cached in the platform keystore
/// ([VaultBiometric]) for the account signed in on the active Quark, and only
/// that one. It is opt-in per device and off by default: [enabled] means an
/// entry exists for the active account, so there is no separate preference
/// to drift out of step with the keystore. Every unlock asks for the
/// biometric again; there is no passcode fallback, and the 15-minute idle
/// lock and the Lock button forget only the key in memory, not the entry
/// (`docs/design/native-autofill-vault.md`, "The idle lock").
///
/// The entry is deleted ([forgetAll]) when the setting is turned off, on a
/// sign-out or a switch of account or Quark, when the vault is started over
/// or deleted from another session (the vault page finds no vault), after a
/// password change on this device, and when the key turns out stale: its
/// fingerprint is not the open vault's, or no item opens under it
/// ([VaultController.cachedKeyStale]). A stale key takes the ciphertext
/// cache for native autofill with it. A face or fingerprint enrolled or
/// removed makes the OS refuse the key; that read deletes it too.
///
/// Every collaborator is a parameter with a real default; tests pass fakes.
class VaultBiometricController extends ChangeNotifier {
  /// Builds a controller.
  VaultBiometricController({
    Future<VaultBiometricSupport> Function()? support,
    Future<Uint8List?> Function(String account)? storedFingerprint,
    Future<void> Function(
      String account,
      Uint8List key,
      Uint8List fingerprint,
      VaultBiometricPrompt prompt,
    )?
    store,
    Future<VaultBiometricEntry> Function(
      String account,
      VaultBiometricPrompt prompt,
    )?
    read,
    Future<void> Function({String? account})? delete,
    Future<void> Function()? clearCache,
    Future<String?> Function()? account,
  }) : _support = support ?? VaultBiometric.support,
       _storedFingerprint =
           storedFingerprint ?? VaultBiometric.storedFingerprint,
       _store = store ?? VaultBiometric.store,
       _read = read ?? VaultBiometric.read,
       _delete = delete ?? VaultBiometric.delete,
       _clearCache = clearCache ?? NativeVaultCache.instance.clear,
       _account = account ?? _activeAccountKey;

  /// The app's controller.
  static final VaultBiometricController instance = VaultBiometricController();

  final Future<VaultBiometricSupport> Function() _support;
  final Future<Uint8List?> Function(String account) _storedFingerprint;
  final Future<void> Function(
    String account,
    Uint8List key,
    Uint8List fingerprint,
    VaultBiometricPrompt prompt,
  )
  _store;
  final Future<VaultBiometricEntry> Function(
    String account,
    VaultBiometricPrompt prompt,
  )
  _read;
  final Future<void> Function({String? account}) _delete;
  final Future<void> Function() _clearCache;
  final Future<String?> Function() _account;

  VaultController? _vault;
  Listenable? _session;
  VaultStatus? _vaultStatus;
  bool _vaultStale = false;

  VaultBiometricSupport _supported = (
    availability: VaultBiometricAvailability.unavailable,
    kind: VaultBiometricKind.biometrics,
  );
  bool _enabled = false;
  bool _busy = false;
  bool _offerDismissed = false;
  Object? _error;

  /// Every keystore change runs in order on this chain, so a wipe cannot
  /// land between a store's prompt and its write.
  Future<void> _queue = Future.value();

  /// Bumped by a session change, so work started for the previous account
  /// drops what it found.
  int _generation = 0;

  /// Whether this device can keep the vault key behind biometrics.
  bool get isAvailable =>
      _supported.availability == VaultBiometricAvailability.available;

  /// Whether biometric unlock is on for the active account on this device.
  bool get enabled => _enabled;

  /// Whether the vault page's lock screen offers the biometric button.
  bool get canUnlock => isAvailable && _enabled;

  /// Whether to offer turning it on: the device can, it is off, the vault
  /// is open, and the offer was not turned down since the app started.
  bool get shouldOffer =>
      isAvailable &&
      !_enabled &&
      !_offerDismissed &&
      _vault?.status == VaultStatus.unlocked;

  /// Whether a prompt or a keystore change is running.
  bool get isBusy => _busy;

  /// Why the last unlock or change did not go through, for
  /// [Errors.vaultBiometric]; null after a cancel.
  Object? get error => _error;

  /// What this device's sensor is called in a sentence: "Face ID",
  /// "Touch ID", or "your fingerprint or face" on Android.
  String get methodName => switch (_supported.kind) {
    VaultBiometricKind.faceId => 'Face ID',
    VaultBiometricKind.touchId => 'Touch ID',
    VaultBiometricKind.biometrics => 'your fingerprint or face',
  };

  /// The lock screen button's label, which is also the setting's title.
  String get settingTitle => switch (_supported.kind) {
    VaultBiometricKind.biometrics => 'Unlock with fingerprint or face',
    _ => 'Unlock with $methodName',
  };

  /// What turning it on means, said before it is turned on.
  String get settingExplanation =>
      'Open your vault on this device with $methodName instead of your '
      "password. Your vault's key is kept in this device's secure storage, "
      'and is asked for with $methodName every time. Anyone who can pass '
      '$methodName on this device can open your vault, so only turn this on '
      'if the faces or fingerprints set up here are all yours. Adding or '
      'removing one turns it off. Locking the vault keeps it on; signing '
      'out, changing your password or starting over turns it off.';

  VaultBiometricPrompt get _unlockPrompt => (
    title: 'Unlock your vault',
    reason: 'Unlock your Quark vault',
    cancel: 'Use password',
  );

  VaultBiometricPrompt get _enablePrompt => (
    title: settingTitle,
    reason: 'Keep your vault key on this device',
    cancel: 'Cancel',
  );

  /// Follows [vault] and [session] for the events that delete the cached
  /// key, and reads whether it is on. Call once at startup; [session]
  /// defaults to the session token.
  void start({required VaultController vault, Listenable? session}) {
    if (_vault != null) return;
    _vault = vault..addListener(_onVaultChanged);
    _vaultStatus = vault.status;
    _session = (session ?? AppSettings.instance.sessionTokenNotifier)
      ..addListener(_onSessionChanged);
    unawaited(refresh());
  }

  /// Reads what the device supports and whether a key is cached for the
  /// active account.
  Future<void> refresh() async {
    final generation = _generation;
    try {
      final supported = await _support();
      final account = await _account();
      final cached =
          account != null &&
          supported.availability == VaultBiometricAvailability.available &&
          await _storedFingerprint(account) != null;
      if (generation != _generation) return;
      _supported = supported;
      _enabled = cached;
    } catch (e) {
      debugPrint('[vault_biometric_controller] refresh failed: $e');
      if (generation != _generation) return;
      _enabled = false;
    }
    notifyListeners();
  }

  /// Turns biometric unlock on: caches the open vault key for the active
  /// account. On Android this shows the biometric prompt. The vault must be
  /// unlocked. Returns whether it is on; on false, [error] says why.
  Future<bool> enable() => _run(() async {
    final vault = _vault;
    final account = await _account();
    if (vault == null || account == null || !isAvailable) {
      throw const VaultBiometricException(VaultBiometricFailure.unavailable);
    }
    final generation = _generation;
    await vault.cacheKey(
      (key, fingerprint) => _store(account, key, fingerprint, _enablePrompt),
    );
    // Signed out while the prompt was up: the wipe after it already ran, so
    // undo the write it could not see.
    if (generation != _generation) {
      await _delete();
      return false;
    }
    _enabled = true;
    return true;
  });

  /// Turns biometric unlock off, deleting the cached key.
  Future<void> disable() async {
    await _run(() async {
      await _delete();
      _enabled = false;
      return true;
    });
  }

  /// Shows the biometric prompt and opens the vault with the cached key.
  /// Returns whether the vault opened. A cancel sets no [error]; a key the
  /// OS refused, or one that turned out stale, is deleted.
  Future<bool> unlock() => _run(() async {
    final vault = _vault;
    final account = await _account();
    if (vault == null || account == null) {
      throw const VaultBiometricException(VaultBiometricFailure.missing);
    }
    final VaultBiometricEntry entry;
    try {
      entry = await _read(account, _unlockPrompt);
    } on VaultBiometricException catch (e) {
      if (e.failure == VaultBiometricFailure.invalidated ||
          e.failure == VaultBiometricFailure.missing ||
          e.failure == VaultBiometricFailure.stale) {
        await _delete();
        _enabled = false;
      }
      if (e.failure == VaultBiometricFailure.stale) await _clearCacheQuietly();
      rethrow;
    }
    if (await vault.unlockWithCachedKey(entry.key, entry.fingerprint)) {
      return true;
    }
    // _onVaultChanged has seen cachedKeyStale and deleted the key.
    throw const MessageException(Errors.vaultBiometricStale);
  });

  /// Drops the offer for the rest of the app's run.
  void dismissOffer() {
    _offerDismissed = true;
    notifyListeners();
  }

  /// Deletes every cached vault key on this device: the wipe on a sign-out,
  /// an account switch, a vault started over or deleted, and a password
  /// change.
  Future<void> forgetAll() => _enqueue(() async {
    await _delete();
    _enabled = false;
    notifyListeners();
  });

  @override
  void dispose() {
    _vault?.removeListener(_onVaultChanged);
    _session?.removeListener(_onSessionChanged);
    super.dispose();
  }

  Future<bool> _run(Future<bool> Function() body) async {
    _busy = true;
    _error = null;
    notifyListeners();
    var done = false;
    await _enqueue(() async {
      try {
        done = await body();
      } catch (e) {
        _error =
            e is VaultBiometricException &&
                e.failure == VaultBiometricFailure.canceled
            ? null
            : e;
      }
    });
    _busy = false;
    notifyListeners();
    return done;
  }

  Future<void> _enqueue(Future<void> Function() run) =>
      _queue = _queue.then((_) => run()).catchError((Object e) {
        debugPrint('[vault_biometric_controller] keystore change failed: $e');
      });

  void _onSessionChanged() {
    _generation++;
    _offerDismissed = false;
    _error = null;
    unawaited(forgetAll());
    unawaited(refresh());
  }

  void _onVaultChanged() {
    final vault = _vault!;
    final status = vault.status;
    final stale = vault.cachedKeyStale;
    final previous = _vaultStatus;
    final wasStale = _vaultStale;
    _vaultStatus = status;
    _vaultStale = stale;
    if (stale && !wasStale) {
      unawaited(_dropStale());
    } else if (status == VaultStatus.noVault &&
        previous != VaultStatus.noVault) {
      // Started over here, or deleted from another session.
      unawaited(forgetAll());
    } else if (status == VaultStatus.unlocked &&
        previous != VaultStatus.unlocked &&
        !vault.unlockedFromCache &&
        _enabled) {
      unawaited(_checkFingerprint(vault.keyFingerprint));
    }
  }

  /// A cached key that no longer opens this vault: delete it and the
  /// ciphertext cache, which is the replaced vault's too.
  Future<void> _dropStale() async {
    await forgetAll();
    await _clearCacheQuietly();
  }

  Future<void> _clearCacheQuietly() async {
    try {
      await _clearCache();
    } catch (e) {
      debugPrint('[vault_biometric_controller] cache left as it was: $e');
    }
  }

  /// After a password unlock, deletes a cached key whose fingerprint is not
  /// the open key's [fingerprint].
  Future<void> _checkFingerprint(Uint8List? fingerprint) async {
    final account = await _account();
    if (fingerprint == null || account == null) return;
    try {
      final cached = await _storedFingerprint(account);
      if (cached != null && !listEquals(cached, fingerprint)) {
        await _dropStale();
      }
    } on VaultBiometricException catch (e) {
      debugPrint('[vault_biometric_controller] fingerprint check: $e');
    }
  }

  /// The account key (`VaultCache.accountKey`) of the account signed in on
  /// the active Quark, or null for none.
  static Future<String?> _activeAccountKey() async {
    final settings = AppSettings.instance;
    final host = settings.activeHost;
    if (host == null || settings.sessionToken == null) return null;
    final username =
        settings.username ?? (await AuthService.checkStatus()).username;
    return username == null ? null : VaultCache.accountKey(host, username);
  }
}
