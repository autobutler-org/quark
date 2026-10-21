import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/vault_biometric_controller.dart';
import 'package:quark/controllers/vault_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/quicktype_identities.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Quark logins in the iOS QuickType bar (#3599): the opt-in setting, and
/// keeping iOS's credential identity store in step with the open vault.
///
/// The store keeps each identity's site and username unencrypted, outside
/// the vault, so this is off by default and per device, and every doubt
/// empties it. While it is on, biometric unlock is on (the extension fills
/// with the key that caches) and the vault is open, the store holds one
/// identity per entry with a URL host and a username, replaced after every
/// unlock and every change to the entries. The identity carries the host,
/// never the full URL, and the item's record, never its password.
///
/// The store is emptied, and the setting turned back off, when the user
/// turns it off, on a sign-out or a switch of account or Quark, when
/// biometric unlock goes off (turned off, or the enrolled faces or
/// fingerprints changed), when the vault is started over or deleted
/// (`noVault`), and when the cached key turns out stale. A failed replace
/// empties it too. Locking the vault, by hand or idle, keeps the identities:
/// the extension asks for Face ID or Touch ID before it fills one, as it
/// does for its own list.
///
/// Every collaborator is a parameter with a real default; tests pass fakes.
class QuickTypeController extends ChangeNotifier {
  /// Builds a controller. [supported] defaults to whether the device has a
  /// QuickType store: iOS only.
  QuickTypeController({
    bool? supported,
    Future<bool> Function()? readOptIn,
    Future<void> Function(bool on)? writeOptIn,
    Future<bool> Function(List<QuickTypeIdentity> identities)? replace,
    Future<void> Function()? clear,
    Future<String?> Function()? account,
  }) : _supported = supported ?? QuickTypeIdentities.isSupported,
       _readOptIn = readOptIn ?? _storedOptIn,
       _writeOptIn = writeOptIn ?? _storeOptIn,
       _replace = replace ?? QuickTypeIdentities.replace,
       _clear = clear ?? QuickTypeIdentities.clear,
       _account = account ?? VaultBiometricController.activeAccountKey;

  /// The app's controller.
  static final QuickTypeController instance = QuickTypeController();

  /// The device preference that holds the opt-in. Absent means off.
  static const optInKey = 'vault_quicktype_suggestions';

  final bool _supported;
  final Future<bool> Function() _readOptIn;
  final Future<void> Function(bool on) _writeOptIn;
  final Future<bool> Function(List<QuickTypeIdentity> identities) _replace;
  final Future<void> Function() _clear;
  final Future<String?> Function() _account;

  VaultController? _vault;
  VaultBiometricController? _biometric;
  Listenable? _session;
  VaultStatus? _vaultStatus;
  bool _vaultStale = false;
  bool _biometricOn = false;

  bool _optIn = false;
  bool _busy = false;
  Object? _error;

  /// The entries as identities are built from, the last time the vault
  /// changed, so typing in the search box does not replace the store.
  List<(int, String, String)>? _seen;

  /// What the last replace was handed, whether or not iOS stored it.
  List<QuickTypeIdentity>? _attempted;

  /// Every store change runs in order on this chain, so a wipe cannot land
  /// before a replace that started earlier.
  Future<void> _queue = Future.value();

  /// Bumped by a session change, so work started for the previous account
  /// drops what it found.
  int _generation = 0;

  /// Whether to offer the setting: the device has a QuickType store and
  /// biometric unlock is on.
  bool get isAvailable => _supported && _biometricOn;

  /// Whether the user opted in on this device.
  bool get enabled => _optIn;

  /// Whether a change of the setting is running.
  bool get isBusy => _busy;

  /// Why the last change did not go through, for `Errors.message`.
  Object? get error => _error;

  /// The setting's name, which is also its switch's label.
  static const settingTitle = 'Show Quark logins in QuickType suggestions';

  /// What turning it on stores and where, said before it is on.
  String get settingExplanation =>
      'Your keyboard suggests your saved logins for the site you are on, and '
      'fills the one you pick after ${_biometric?.methodName ?? 'Face ID'}. '
      'To do this, iOS stores the site address and username of each login '
      'unencrypted on this device, outside your vault. Passwords stay '
      'encrypted. Signing out, starting over or turning off '
      '${_biometric?.methodName ?? 'Face ID'} unlock turns this off and '
      'removes them.';

  /// Follows [vault], [biometric] and [session] for what replaces or
  /// empties the store, and reads the opt-in. Call once at startup;
  /// [session] defaults to the session token. Does nothing off iOS.
  void start({
    required VaultController vault,
    required VaultBiometricController biometric,
    Listenable? session,
  }) {
    if (!_supported || _vault != null) return;
    _vault = vault..addListener(_onVaultChanged);
    _vaultStatus = vault.status;
    _vaultStale = vault.cachedKeyStale;
    _biometric = biometric..addListener(_onBiometricChanged);
    _biometricOn = biometric.enabled;
    _session = (session ?? AppSettings.instance.sessionTokenNotifier)
      ..addListener(_onSessionChanged);
    unawaited(
      _enqueue(() async {
        final generation = _generation;
        var on = false;
        try {
          on = await _readOptIn();
        } catch (e) {
          debugPrint('[quicktype_controller] opt-in unreadable: $e');
        }
        if (generation != _generation) return;
        _optIn = on;
        notifyListeners();
        // Off means empty, whatever an earlier run left behind.
        if (!on) return _wipe();
        _seen = null;
        await _sync();
      }),
    );
  }

  /// Turns the setting on, filling the store from the open vault, or off,
  /// emptying it. Returns whether it is now as asked; on false, [error]
  /// says why. Turning it off empties the store even when the preference
  /// does not save.
  Future<bool> setEnabled(bool on) async {
    _busy = true;
    _error = null;
    notifyListeners();
    var done = false;
    await _enqueue(() async {
      try {
        if (on) {
          await _writeOptIn(true);
          _optIn = true;
          _attempted = null;
          await _sync();
        } else {
          await _turnOff();
        }
        done = true;
      } catch (e) {
        _error = e;
      }
    });
    _busy = false;
    notifyListeners();
    return done;
  }

  @override
  void dispose() {
    _vault?.removeListener(_onVaultChanged);
    _biometric?.removeListener(_onBiometricChanged);
    _session?.removeListener(_onSessionChanged);
    super.dispose();
  }

  /// Turns the opt-in off and empties the store. The store is emptied
  /// first, and whatever fails is thrown once both have been tried.
  Future<void> _turnOff() async {
    _optIn = false;
    Object? failure;
    try {
      await _wipe();
    } catch (e) {
      failure = e;
    }
    try {
      await _writeOptIn(false);
    } catch (e) {
      failure ??= e;
    }
    if (failure != null) throw failure;
  }

  /// Replaces the store with the open vault's identities, when the user
  /// opted in, biometric unlock is on and the vault is open. A replace
  /// that fails empties the store.
  Future<void> _sync() async {
    final vault = _vault;
    if (!_optIn ||
        !_biometricOn ||
        vault == null ||
        vault.status != VaultStatus.unlocked ||
        vault.cachedKeyStale) {
      return;
    }
    final generation = _generation;
    final account = await _account();
    if (account == null || generation != _generation) return;
    final identities = [
      for (final item in vault.entries)
        if (item.data.urlHost.isNotEmpty && item.data.username.isNotEmpty)
          (
            domain: item.data.urlHost,
            username: item.data.username,
            record: '$account/${item.id}',
          ),
    ];
    if (listEquals(identities, _attempted)) return;
    _attempted = identities;
    try {
      await _replace(identities);
    } catch (_) {
      await _wipe();
      rethrow;
    }
  }

  /// Empties the store.
  Future<void> _wipe() async {
    _attempted = null;
    await _clear();
  }

  Future<void> _enqueue(Future<void> Function() run) =>
      _queue = _queue.then((_) => run()).catchError((Object e) {
        debugPrint('[quicktype_controller] store change failed: $e');
      });

  /// Turns the opt-in off and empties the store, outside a user action.
  void _revoke() {
    final wasOn = _optIn;
    _optIn = false;
    _error = null;
    unawaited(_enqueue(_turnOff));
    if (wasOn) notifyListeners();
  }

  void _onSessionChanged() {
    _generation++;
    _seen = null;
    _revoke();
  }

  void _onBiometricChanged() {
    final on = _biometric!.enabled;
    if (on == _biometricOn) return;
    _biometricOn = on;
    if (on) {
      notifyListeners();
    } else {
      _revoke();
    }
  }

  void _onVaultChanged() {
    final vault = _vault!;
    final status = vault.status;
    final stale = vault.cachedKeyStale;
    final previous = _vaultStatus;
    final wasStale = _vaultStale;
    _vaultStatus = status;
    _vaultStale = stale;
    if ((stale && !wasStale) ||
        (status == VaultStatus.noVault && previous != VaultStatus.noVault)) {
      // A replaced vault, or one started over or deleted.
      _seen = null;
      _revoke();
      return;
    }
    if (status != VaultStatus.unlocked) {
      // The next unlock replaces the store whatever it held.
      _seen = null;
      _attempted = null;
      return;
    }
    final seen = [
      for (final item in vault.entries)
        (item.id, item.data.urlHost, item.data.username),
    ];
    if (listEquals(seen, _seen)) return;
    _seen = seen;
    unawaited(_enqueue(_sync));
  }

  static Future<bool> _storedOptIn() async =>
      (await SharedPreferences.getInstance()).getBool(optInKey) ?? false;

  static Future<void> _storeOptIn(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    if (on) {
      await prefs.setBool(optInKey, true);
    } else {
      await prefs.remove(optInKey);
    }
  }
}
