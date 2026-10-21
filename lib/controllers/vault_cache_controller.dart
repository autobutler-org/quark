import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/vault_controller.dart';
import 'package:quark/models/vault_item.dart';
import 'package:quark/models/vault_key.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/native_vault_cache.dart';
import 'package:quark/services/vault_cache.dart';
import 'package:quark/services/vault_service.dart';

/// The account a cache file belongs to: the Quark's address and the
/// username signed in there.
typedef VaultCacheAccount = ({String host, String username});

/// Keeps the signed-in account's vault ciphertext on the device for native
/// autofill (#3596), as [VaultCache] lays it out and [NativeVaultCache]
/// stores it.
///
/// The list is ciphertext and needs only the session, so the cache follows
/// the vault whether the vault page is locked or not. [start] writes it
/// once, and it is written again on every `vault_changed` and `resync`
/// event, and whenever the vault page unlocks or finds no vault. A sign-out
/// or a switch of account or Quark wipes it before the next account's is
/// written; so does a vault deleted from any session. A refresh that fails
/// keeps the last cache, so autofill still works offline.
///
/// It never sees the vault key or a decrypted item: what it writes is the
/// Quark's own response. Every collaborator is a parameter with a real
/// default; tests pass fakes.
class VaultCacheController {
  /// Builds a controller. [enabled] defaults to iOS and Android, the
  /// platforms with an autofill to share with.
  VaultCacheController({
    Future<WrappedVaultKey?> Function()? fetchKey,
    Future<List<VaultCiphertext>> Function()? listItems,
    Future<VaultCacheAccount?> Function()? account,
    Future<void> Function(String accountKey, String contents)? write,
    Future<void> Function()? clear,
    DateTime Function()? now,
    bool? enabled,
  }) : _fetchKey = fetchKey ?? VaultService.fetchKey,
       _listItems = listItems ?? VaultService.listItems,
       _account = account ?? _signedInAccount,
       _write = write ?? NativeVaultCache.instance.write,
       _clear = clear ?? NativeVaultCache.instance.clear,
       _now = now ?? DateTime.now,
       _enabled =
           enabled ??
           (!kIsWeb &&
               (defaultTargetPlatform == TargetPlatform.iOS ||
                   defaultTargetPlatform == TargetPlatform.android));

  /// The app's controller.
  static final VaultCacheController instance = VaultCacheController();

  final Future<WrappedVaultKey?> Function() _fetchKey;
  final Future<List<VaultCiphertext>> Function() _listItems;
  final Future<VaultCacheAccount?> Function() _account;
  final Future<void> Function(String accountKey, String contents) _write;
  final Future<void> Function() _clear;
  final DateTime Function() _now;
  final bool _enabled;

  StreamSubscription<FileEvent>? _events;
  Listenable? _session;
  VaultController? _vault;
  VaultStatus? _vaultStatus;

  /// Every write and wipe runs in order on this chain.
  Future<void> _queue = Future.value();

  /// Bumped by a session change, so a refresh that started under the
  /// previous account drops what it fetched.
  int _generation = 0;

  /// Follows the events, the session and the vault page, and writes the
  /// cache once. Call once at startup; the arguments are for tests.
  void start({
    Stream<FileEvent>? events,
    Listenable? session,
    VaultController? vault,
  }) {
    if (!_enabled || _events != null) return;
    _events = (events ?? EventsService.instance.events).listen(_onEvent);
    _session = (session ?? AppSettings.instance.sessionTokenNotifier)
      ..addListener(_onSessionChanged);
    _vault = vault?..addListener(_onVaultChanged);
    _vaultStatus = vault?.status;
    unawaited(refresh());
  }

  /// Writes the signed-in account's items as the Quark lists them now, or
  /// wipes the cache when nobody is signed in or the account has no vault.
  Future<void> refresh() => _enqueue(_sync);

  /// Stops following everything. The cache stays on disk.
  void dispose() {
    _events?.cancel();
    _session?.removeListener(_onSessionChanged);
    _vault?.removeListener(_onVaultChanged);
  }

  Future<void> _sync() async {
    final generation = _generation;
    final account = await _account();
    if (generation != _generation) return;
    if (account == null) return _clear();
    if (await _fetchKey() == null) {
      return generation == _generation ? _clear() : null;
    }
    final items = await _listItems();
    if (generation != _generation) return;
    await _write(
      VaultCache.accountKey(account.host, account.username),
      VaultCache.encode(
        host: account.host,
        username: account.username,
        items: items,
        syncedAt: _now(),
      ),
    );
  }

  Future<void> _enqueue(Future<void> Function() run) =>
      _queue = _queue.then((_) => run()).catchError((Object e) {
        debugPrint('[vault_cache_controller] cache left as it was: $e');
      });

  void _onEvent(FileEvent event) {
    if (event.kind == 'vault_changed' || event.kind == 'resync') {
      unawaited(refresh());
    }
  }

  void _onSessionChanged() {
    _generation++;
    unawaited(_enqueue(_clear));
    unawaited(refresh());
  }

  void _onVaultChanged() {
    final status = _vault?.status;
    if (status == _vaultStatus) return;
    _vaultStatus = status;
    if (status == VaultStatus.unlocked || status == VaultStatus.noVault) {
      unawaited(refresh());
    }
  }

  /// The account signed in on the active Quark, or null for none.
  static Future<VaultCacheAccount?> _signedInAccount() async {
    final settings = AppSettings.instance;
    final host = settings.activeHost;
    if (host == null || settings.sessionToken == null) return null;
    final username =
        settings.username ?? (await AuthService.checkStatus()).username;
    return username == null ? null : (host: host, username: username);
  }
}
