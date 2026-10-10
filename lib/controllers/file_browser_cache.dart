import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/listing_snapshot_config.dart';
import 'package:quark/utils/listing_snapshot_store.dart';

/// In-memory cache of file listings keyed by folder path.
///
/// Shared across [FileBrowserPage] instances so that go_router rebuilds (which
/// recreate the widget) can display the previous result immediately while a
/// fresh fetch is in flight.
///
/// The folders a cold launch opens, the root and the account's home, are
/// also written to disk, and [hydrate] reads them back on the next launch so
/// the Files page has its last content before the first listing answers
/// (#1781). No more than [ListingSnapshotConfig.maxItemsPerFolder] entries of
/// each are written, and only what the listing itself returned.
///
/// Everything belongs to the Quark and account signed in. Once either
/// changes, or the session ends, the listings and the snapshot on disk are
/// both forgotten, so one account's files never show for another.
///
/// Also tracks which file (if any) is currently open in a viewer, so that when
/// a URL update triggers a background go_router rebuild, the rebuilt page
/// doesn't try to open a second viewer on top of the existing one.
class FileBrowserCache {
  /// [store], [account] and [accountChanges] default to this platform's
  /// snapshot store, the Quark and account signed in, and the session token;
  /// a test passes its own.
  FileBrowserCache({
    ListingSnapshotStore? store,
    ({String host, String username})? Function()? account,
    Listenable? accountChanges,
  }) : _store = store ?? listingSnapshotStore,
       _account = account ?? _activeAccount {
    // Signing out has to clear the disk right away, not at the next lookup.
    (accountChanges ?? AppSettings.instance.sessionTokenNotifier).addListener(
      _enterScope,
    );
  }

  /// The cache every Files page shares. Assignable so a test can give the
  /// page one with its own store.
  static FileBrowserCache instance = FileBrowserCache();

  /// The name the Files snapshot is stored under.
  static const _snapshotName = 'files';

  final ListingSnapshotStore _store;
  final ({String host, String username})? Function() _account;

  final Map<String, List<FileNode>> _cache = {};

  /// The scope everything in [_cache] and on disk was kept for. Starts as
  /// the scope at first use, so a launch never clears what it is about to
  /// read.
  late String? _keptFor = _scope();

  /// The read [hydrate] started for [_keptFor], if any.
  Future<void>? _hydration;

  /// Bumped whenever the listings are forgotten, so a read that was under
  /// way does not put them back.
  int _generation = 0;

  /// Null with nobody signed in. Keyed by the Quark's identity rather than
  /// `apiBaseUrl`: that one moves to the remote-access address whenever
  /// `ConnectionController` switches, and a snapshot keyed by it would be
  /// thrown away on every launch away from home.
  static ({String host, String username})? _activeAccount() {
    final settings = AppSettings.instance;
    final host = settings.activeHost;
    if (host == null || settings.sessionToken == null) return null;
    return (host: host, username: settings.username ?? '');
  }

  String? _scope() {
    final account = _account();
    return account == null ? null : '${account.host}\u0000${account.username}';
  }

  /// Forgets what another Quark or account left, in memory and on disk.
  void _enterScope() {
    final current = _scope();
    if (current == _keptFor) return;
    _keptFor = current;
    _forget();
  }

  void _forget() {
    _cache.clear();
    _hydration = null;
    _generation++;
    unawaited(_store.clear());
  }

  List<FileNode>? get(String path) {
    _enterScope();
    return _cache[path];
  }

  void put(String path, List<FileNode> files) {
    _enterScope();
    _cache[path] = List.unmodifiable(files);
    final account = _account();
    final scope = _keptFor;
    if (account == null || scope == null) return;
    // The only two folders a cold launch opens: see `landingPath`.
    final landing = {'', homePath(account.username)};
    if (!landing.contains(path)) return;
    unawaited(
      _store.write(_snapshotName, {
        for (final folder in landing)
          if (_cache[folder] case final kept?)
            folder: [
              for (final node in kept.take(
                ListingSnapshotConfig.maxItemsPerFolder,
              ))
                node.toJson(),
            ],
      }, scope: scope),
    );
  }

  void evict(String path) {
    _enterScope();
    _cache.remove(path);
  }

  /// Forgets every listing, and the snapshot on disk with them.
  void clear() {
    _keptFor = _scope();
    _forget();
  }

  /// Reads the snapshot the last launch left for this Quark and account
  /// into the cache, once. A listing already fetched this session is kept
  /// over the snapshot's. Never throws, and with nobody signed in it clears
  /// the disk instead.
  ///
  /// Not for awaiting before the first frame: start it early and look the
  /// folder up again once it completes.
  Future<void> hydrate() {
    _enterScope();
    return _hydration ??= _hydrate();
  }

  Future<void> _hydrate() async {
    final scope = _keptFor;
    if (scope == null) return _store.clear();
    final generation = _generation;
    final data = await _store.read(_snapshotName, scope: scope);
    // Forgotten, or signed in as someone else, while the read was out.
    if (data == null || generation != _generation || scope != _scope()) return;
    try {
      final listings = {
        for (final MapEntry(:key, :value)
            in (data as Map<String, dynamic>).entries)
          key: List<FileNode>.unmodifiable([
            for (final node in value as List<dynamic>)
              FileNode.fromJson(node as Map<String, dynamic>),
          ]),
      };
      listings.forEach((path, files) => _cache.putIfAbsent(path, () => files));
    } catch (e) {
      debugPrint('[file_browser_cache.dart] dropped a malformed snapshot: $e');
      unawaited(_store.clear());
    }
  }

  // ── Open-file tracking ────────────────────────────────────────────────────

  String? _openFilePath;

  /// Keys are normalized on the way in and out so callers cannot disagree about
  /// the format. `markFileOpen` used to store the raw path while the
  /// `didUpdateWidget` guard looked it up normalized, which left that guard
  /// dead for every path missing a leading slash (#1604).
  static String _key(String path) => normalizePath(path);

  /// Mark [path] as currently open in a viewer/editor overlay.
  void markFileOpen(String path) => _openFilePath = _key(path);

  /// Clear the open-file marker once the viewer/editor for [path] is dismissed.
  ///
  /// Scoped to [path] so a viewer that closes late cannot clear a marker set by
  /// whatever opened after it.
  void markFileClosed(String path) {
    if (_openFilePath == _key(path)) {
      _openFilePath = null;
    }
  }

  /// Clear the open-file marker regardless of which path set it.
  void clearOpenFile() => _openFilePath = null;

  /// Returns true if [path] is already being shown — prevents a second viewer
  /// from being pushed by a background [FileBrowserPage] rebuild.
  bool isFileOpen(String path) =>
      _openFilePath != null && _openFilePath == _key(path);

  /// The path currently marked open, normalized. Null when nothing is open.
  String? get openFilePath => _openFilePath;
}
