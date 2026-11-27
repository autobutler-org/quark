import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:quark/models/kept_album.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/services/album_service.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/kept_albums_store.dart';
import 'package:quark/services/photo_disk_cache.dart';
import 'package:quark/services/photo_preview_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark/utils/kept_albums_config.dart';
import 'package:quark/utils/metered_network.dart';

/// Downloads the albums kept on this phone for offline viewing (#4222) and
/// keeps them in step with the Quark.
///
/// Each kept album holds every photo's preview, and its original too when
/// the person chose full originals, in `PhotoDiskCache`'s kept stores, out of
/// reach of the cache's budget. A sync lists the album, keeps what is new,
/// and releases what left it, unless another kept album still holds it. It
/// runs on [start], after a keep, when the Quark reports a change (debounced
/// by [KeptAlbumsConfig.syncDebounce]), when this phone adds or removes an
/// album's photo, when the app comes back to the front, and every
/// [KeptAlbumsConfig.retryInterval] while work is left. Over mobile data it
/// waits, unless the album allows it.
///
/// Only the active Quark and account's albums sync; [albums] lists those.
/// Every service is a constructor parameter, so a test runs a sync with
/// fakes and no network.
class KeptAlbumsController extends ChangeNotifier with WidgetsBindingObserver {
  /// Creates the controller. Every parameter defaults to the real service.
  KeptAlbumsController({
    Future<List<KeptAlbum>> Function() load = KeptAlbumsStore.load,
    Future<void> Function(List<KeptAlbum>) save = KeptAlbumsStore.save,
    Future<List<PhotoAlbumItem>> Function(int albumId) listAlbumItems =
        _fetchAlbumItems,
    Future<Uint8List?> Function(String path, {String? serial}) fetchPreview =
        PhotoPreviewService.fetchPreviewBytes,
    Future<Uint8List?> Function(String path, {String? serial}) fetchPhoto =
        FilesService.fetchPhotoBytes,
    KeepPhoto keep = PhotoDiskCache.keep,
    ReleasePhoto release = PhotoDiskCache.release,
    Future<bool> Function() isMetered = isOnMeteredNetwork,
    Stream<FileEvent>? events,
    Stream<int>? albumChanges,
    ({String? host, String? account}) Function()? scope,
  }) : _load = load,
       _save = save,
       _listAlbumItems = listAlbumItems,
       _fetchPreview = fetchPreview,
       _fetchPhoto = fetchPhoto,
       _keep = keep,
       _release = release,
       _isMetered = isMetered,
       _events = events,
       _albumChanges = albumChanges,
       _scope = scope ?? _activeScope;

  /// The controller the app runs, started from `main`.
  static final instance = KeptAlbumsController();

  /// The album's photos from the Quark itself, never the copy a kept album
  /// lists offline, which would pass for an empty album already synced.
  static Future<List<PhotoAlbumItem>> _fetchAlbumItems(int albumId) =>
      AlbumService.fetchAlbumItems(albumId);

  static ({String? host, String? account}) _activeScope() => (
    host: AppSettings.instance.activeHost,
    account: AppSettings.instance.username,
  );

  final Future<List<KeptAlbum>> Function() _load;
  final Future<void> Function(List<KeptAlbum>) _save;
  final Future<List<PhotoAlbumItem>> Function(int albumId) _listAlbumItems;
  final Future<Uint8List?> Function(String path, {String? serial})
  _fetchPreview;
  final Future<Uint8List?> Function(String path, {String? serial}) _fetchPhoto;
  final KeepPhoto _keep;
  final ReleasePhoto _release;
  final Future<bool> Function() _isMetered;
  final Stream<FileEvent>? _events;
  final Stream<int>? _albumChanges;
  final ({String? host, String? account}) Function() _scope;

  /// Every kept album, every Quark's and account's.
  List<KeptAlbum> _all = const [];
  final Map<int, KeptAlbumProgress> _progress = {};
  final List<StreamSubscription<Object>> _subscriptions = [];
  Timer? _debounce;
  Timer? _retry;
  Future<void>? _syncing;
  bool _syncAgain = false;
  bool _started = false;
  bool _disposed = false;

  /// The active Quark and account's kept albums.
  List<KeptAlbum> get albums {
    final scope = _scope();
    return [
      for (final album in _all)
        if (album.belongsTo(scope.host, scope.account)) album,
    ];
  }

  /// Whether the album [albumId] is kept on this phone.
  bool isKept(int albumId) => albums.any((album) => album.albumId == albumId);

  /// Where the album [albumId]'s download stands, or null when it is not
  /// kept.
  KeptAlbumProgress? progressOf(int albumId) {
    for (final album in albums) {
      if (album.albumId != albumId) continue;
      return _progress[albumId] ??
          (album.complete
              ? KeptAlbumProgress.ready
              : const KeptAlbumProgress(KeptAlbumStatus.pending));
    }
    return null;
  }

  /// Loads the kept albums, listens for changes and syncs. Safe to call
  /// more than once; only the first call does anything.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _subscriptions
      ..add(
        (_events ?? EventsService.instance.events).listen((event) {
          if (event.changesListing && albums.isNotEmpty) _scheduleSync();
        }),
      )
      ..add(
        (_albumChanges ?? AlbumService.changes).listen((albumId) {
          if (isKept(albumId)) _scheduleSync();
        }),
      );
    _all = await _load();
    _notify();
    await sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && albums.isNotEmpty) {
      unawaited(sync());
    }
  }

  /// Keeps the album [albumId], named [name], on this phone and starts its
  /// download: its previews, and its full originals too when [originals].
  /// It waits for Wi-Fi unless [allowMobileData].
  Future<void> keepAlbum({
    required int albumId,
    required String name,
    bool originals = false,
    bool allowMobileData = false,
  }) async {
    final scope = _scope();
    final host = scope.host;
    final account = scope.account;
    if (host == null || account == null || isKept(albumId)) return;
    _all = [
      ..._all,
      KeptAlbum(
        albumId: albumId,
        name: name,
        host: host,
        account: account,
        originals: originals,
        allowMobileData: allowMobileData,
      ),
    ];
    await _save(_all);
    _notify();
    await sync();
  }

  /// Stops keeping the album [albumId], freeing every photo no other kept
  /// album holds.
  ///
  /// A sync under way for the album stops after the photo it is on, and
  /// frees what it kept itself.
  Future<void> stopKeeping(int albumId) => _forget(albumId);

  /// Drops the album [albumId] from the kept ones and frees its photos.
  Future<void> _forget(int albumId) async {
    final album = _find(albumId);
    if (album == null) return;
    _all = [
      for (final other in _all)
        if (!identical(other, album)) other,
    ];
    _progress.remove(albumId);
    await _save(_all);
    _notify();
    await _releaseUnused(album, const []);
  }

  /// Brings every kept album of the active Quark and account up to date.
  /// A call while one runs makes it run once more when it ends.
  Future<void> sync() async {
    final running = _syncing;
    if (running != null) {
      _syncAgain = true;
      return running;
    }
    final run = _syncing = _syncAll();
    try {
      await run;
    } finally {
      _syncing = null;
    }
    if (_syncAgain && !_disposed) {
      _syncAgain = false;
      await sync();
    }
  }

  Future<void> _syncAll() async {
    _retry?.cancel();
    var unfinished = false;
    for (final album in albums) {
      if (_disposed) return;
      if (!await _syncAlbum(album)) unfinished = true;
    }
    if (unfinished && !_disposed) {
      _retry = Timer(KeptAlbumsConfig.retryInterval, () => unawaited(sync()));
    }
  }

  /// Syncs [album]. Answers whether it is now complete.
  Future<bool> _syncAlbum(KeptAlbum album) async {
    final id = album.albumId;
    if (!album.allowMobileData && await _isMetered()) {
      _setProgress(id, const KeptAlbumProgress(KeptAlbumStatus.waitingForWifi));
      return false;
    }
    final List<PhotoAlbumItem> items;
    try {
      items = await _listAlbumItems(id);
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        // The album is gone from the Quark; so is the keep.
        await _forget(id);
        return true;
      }
      _setProgress(id, const KeptAlbumProgress(KeptAlbumStatus.failed));
      return false;
    } on Exception {
      _setProgress(id, const KeptAlbumProgress(KeptAlbumStatus.failed));
      return false;
    }

    var bytes = 0;
    var done = 0;
    var complete = true;
    _setProgress(id, KeptAlbumProgress.downloading(0, items.length));
    for (final item in items) {
      if (_disposed) return false;
      try {
        bytes += await _keepItem(album, item);
      } on Exception {
        // The connection dropped, or the Quark could not serve this one;
        // what was kept stays, and the next sync carries on from there.
        complete = false;
      }
      if (_find(id) == null) {
        // Stopped keeping mid-sync: free what this sync kept since.
        await _releaseUnused(album.copyWith(items: items), const []);
        return true;
      }
      done++;
      _setProgress(id, KeptAlbumProgress.downloading(done, items.length));
    }

    final current = _find(id);
    if (current == null) return true;
    final updated = current.copyWith(
      items: items,
      keptBytes: bytes,
      complete: complete,
    );
    _all = [
      for (final other in _all) identical(other, current) ? updated : other,
    ];
    await _save(_all);
    await _releaseUnused(album, items);
    _setProgress(
      id,
      complete
          ? KeptAlbumProgress.ready
          : const KeptAlbumProgress(KeptAlbumStatus.failed),
    );
    return complete;
  }

  /// Keeps [item]'s renditions for [album]. Answers how many bytes they
  /// take.
  Future<int> _keepItem(KeptAlbum album, PhotoAlbumItem item) async {
    final path = item.relPath;
    final serial = item.deviceSerial;
    Future<int> keep(
      KeptRendition rendition,
      Future<Uint8List?> Function() download,
    ) async =>
        await _keep(
          path,
          serial: serial,
          host: album.host,
          account: album.account,
          rendition: rendition,
          download: download,
        ) ??
        0;

    final heic = _isHeic(path);
    var bytes = 0;
    var needsOriginal = album.originals && !heic;
    try {
      bytes += await keep(
        KeptRendition.preview,
        // A HEIC's preview is its stored JPEG, which the viewer reads
        // through the same key.
        () => heic
            ? _fetchPhoto(path, serial: serial)
            : _fetchPreview(path, serial: serial),
      );
    } on ApiException {
      if (heic) rethrow;
      // The Quark renders no preview of this one; the viewer falls back to
      // the original, so keep that.
      needsOriginal = true;
    }
    if (needsOriginal) {
      bytes += await keep(
        KeptRendition.original,
        () => _fetchPhoto(path, serial: serial),
      );
    }
    return bytes;
  }

  /// Releases the photos [album] kept that are not in [items] and that no
  /// other kept album of its Quark and account holds.
  Future<void> _releaseUnused(
    KeptAlbum album,
    List<PhotoAlbumItem> items,
  ) async {
    String photoKey(PhotoAlbumItem item) =>
        '${item.deviceSerial}\u0000${item.relPath}';
    final stillHeld = {for (final item in items) photoKey(item)};
    final heldElsewhere = {
      for (final other in _all)
        if (other.albumId != album.albumId &&
            other.belongsTo(album.host, album.account))
          for (final item in other.items) photoKey(item),
    };
    for (final item in album.items) {
      final key = photoKey(item);
      if (stillHeld.contains(key) || heldElsewhere.contains(key)) continue;
      for (final rendition in KeptRendition.values) {
        await _release(
          item.relPath,
          serial: item.deviceSerial,
          host: album.host,
          account: album.account,
          rendition: rendition,
        );
      }
    }
  }

  KeptAlbum? _find(int albumId) {
    final scope = _scope();
    for (final album in _all) {
      if (album.albumId == albumId &&
          album.belongsTo(scope.host, scope.account)) {
        return album;
      }
    }
    return null;
  }

  static bool _isHeic(String path) =>
      heicImageExtensions.contains(fileExtension(path));

  void _scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(KeptAlbumsConfig.syncDebounce, () => unawaited(sync()));
  }

  void _setProgress(int albumId, KeptAlbumProgress progress) {
    _progress[albumId] = progress;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _retry?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// `PhotoDiskCache.keep`'s shape, which a test fakes.
typedef KeepPhoto =
    Future<int?> Function(
      String path, {
      String? serial,
      String? host,
      String? account,
      required KeptRendition rendition,
      required Future<Uint8List?> Function() download,
    });

/// `PhotoDiskCache.release`'s shape, which a test fakes.
typedef ReleasePhoto =
    Future<void> Function(
      String path, {
      String? serial,
      String? host,
      String? account,
      required KeptRendition rendition,
    });

/// What a kept album's download is doing.
enum KeptAlbumStatus {
  /// Not synced since the app started.
  pending,

  /// Downloading; [KeptAlbumProgress.done] of [KeptAlbumProgress.total].
  downloading,

  /// On mobile data, which the album does not allow.
  waitingForWifi,

  /// The last sync could not reach the Quark or fetch every photo; it tries
  /// again.
  failed,

  /// Every photo is on the phone.
  ready,
}

/// Where a kept album's download stands.
@immutable
class KeptAlbumProgress {
  /// A [status] with no counts.
  const KeptAlbumProgress(this.status) : done = 0, total = 0;

  /// [done] of [total] photos kept so far.
  const KeptAlbumProgress.downloading(this.done, this.total)
    : status = KeptAlbumStatus.downloading;

  /// Every photo kept.
  static const KeptAlbumProgress ready = KeptAlbumProgress(
    KeptAlbumStatus.ready,
  );

  /// What the download is doing.
  final KeptAlbumStatus status;

  /// How many photos are kept so far, while [status] is downloading.
  final int done;

  /// How many photos the album holds, while [status] is downloading.
  final int total;
}
