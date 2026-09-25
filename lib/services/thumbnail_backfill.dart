import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:quark/models/thumbnail_probe.dart';
import 'package:quark/services/client_thumbnails.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/client_thumbnail_config.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_kind.dart';

/// Renders the thumbnail of a video or HEIC the Quark cannot make one for,
/// when a tile showing it comes up empty, and uploads it (#2381).
///
/// This is how a thumbnail reaches a file no client rendered at upload: one
/// sent from a browser that could not decode it, extracted from an archive,
/// on a USB drive, synced by a backup, or whose cached thumbnail was lost to a
/// move or rename. The Quark marks such a miss with `clientRender`.
///
/// Bounded so a grid of videos cannot swamp the phone or the Quark: only
/// tiles on screen ask, [maxConcurrent] run at once, a file version that
/// failed is not tried again this session, each attempt has [budget], and a
/// folder that refused an upload (read-only) is skipped from then on. Nothing
/// here throws or blocks the caller; it answers whether the tile should load
/// again.
class ThumbnailBackfill {
  ThumbnailBackfill({
    Future<ThumbnailProbe> Function(String path, {String? serial})? probe,
    Future<Uint8List> Function(String path, {String? serial})? downloadOriginal,
    Future<Uint8List?> Function(String name, Uint8List bytes)? renderFromBytes,
    Future<Uint8List?> Function(String name, Uri url)? renderVideoFromUrl,
    Uri Function(String path, {String? serial})? mediaUrl,
    Future<void> Function({
      required String path,
      String? serial,
      required Uint8List thumbnail,
    })?
    putThumbnail,
    this.maxConcurrent = 2,
    this.budget = ClientThumbnailConfig.renderTimeout,
  }) : _probe = probe ?? FilesService.probeThumbnail,
       _downloadOriginal =
           downloadOriginal ?? FilesService.downloadOriginalBytes,
       _renderFromBytes = renderFromBytes ?? renderThumbnailFromBytes,
       _renderVideoFromUrl = renderVideoFromUrl ?? renderVideoThumbnailFromUrl,
       _mediaUrl = mediaUrl ?? FilesService.constructMediaUrl,
       _putThumbnail = putThumbnail ?? FilesService.putThumbnail;

  /// The app's one backfill, shared by every tile.
  static final ThumbnailBackfill instance = ThumbnailBackfill();

  /// How many files are probed, rendered and uploaded at once.
  final int maxConcurrent;

  /// How long one file may take, download and render included.
  final Duration budget;

  final Future<ThumbnailProbe> Function(String path, {String? serial}) _probe;
  final Future<Uint8List> Function(String path, {String? serial})
  _downloadOriginal;
  final Future<Uint8List?> Function(String name, Uint8List bytes)
  _renderFromBytes;
  final Future<Uint8List?> Function(String name, Uri url) _renderVideoFromUrl;
  final Uri Function(String path, {String? serial}) _mediaUrl;
  final Future<void> Function({
    required String path,
    String? serial,
    required Uint8List thumbnail,
  })
  _putThumbnail;

  /// File versions tried this session, as `serial|path|modTime`.
  final Set<String> _attempted = {};

  /// Folders whose upload was refused, as `serial|folder`.
  final Set<String> _readOnlyFolders = {};

  /// Attempts in flight, by `serial|path`, so two tiles share one.
  final Map<String, Future<bool>> _inFlight = {};

  final Queue<Completer<void>> _waiting = Queue();
  int _running = 0;

  /// Fills in the thumbnail of the file at [path] if the Quark has none and
  /// says a client may render it. True when the tile should load its
  /// thumbnail again: the Quark now has one. [stillWanted] is asked when the
  /// file's turn comes; a tile that has scrolled away answers false.
  Future<bool> fill({
    required String path,
    String? serial,
    bool Function()? stillWanted,
  }) {
    if (!needsClientRender(path)) return Future.value(false);
    if (_readOnlyFolders.contains(_folderKey(path, serial))) {
      return Future.value(false);
    }
    final key = '${serial ?? ''}|$path';
    // A block body: whenComplete waits on a future its callback returns, and
    // remove would return this very one.
    return _inFlight[key] ??= _fill(path, serial, stillWanted).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<bool> _fill(
    String path,
    String? serial,
    bool Function()? stillWanted,
  ) async {
    await _acquire();
    try {
      if (stillWanted != null && !stillWanted()) return false;
      final probe = await _probe(path, serial: serial);
      if (probe.served) return true;
      if (!probe.clientRender) return false;
      if (!_attempted.add('${serial ?? ''}|$path|${probe.modTime}')) {
        return false;
      }
      final thumbnail = await _render(path, serial).timeout(budget);
      if (thumbnail == null) return false;
      await _putThumbnail(path: path, serial: serial, thumbnail: thumbnail);
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 403) _readOnlyFolders.add(_folderKey(path, serial));
      return false;
    } catch (e) {
      debugPrint('[thumbnail_backfill.dart] No thumbnail for $path: $e');
      return false;
    } finally {
      _release();
    }
  }

  Future<Uint8List?> _render(String path, String? serial) async {
    final name = path.split('/').last;
    if (fileKindForName(name) == FileKind.video) {
      // Streamed: the platform reads only what the frame needs.
      return _renderVideoFromUrl(name, _mediaUrl(path, serial: serial));
    }
    // A HEIC is a few MB, and no decoder here takes it as a stream.
    return _renderFromBytes(
      name,
      await _downloadOriginal(path, serial: serial),
    );
  }

  String _folderKey(String path, String? serial) {
    final slash = path.lastIndexOf('/');
    return '${serial ?? ''}|${slash < 0 ? '' : path.substring(0, slash)}';
  }

  Future<void> _acquire() {
    if (_running < maxConcurrent) {
      _running++;
      return Future.value();
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    return turn.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _running--;
    }
  }
}
