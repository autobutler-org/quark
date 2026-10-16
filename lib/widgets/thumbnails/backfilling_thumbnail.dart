import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:quark/services/thumbnail_backfill.dart';
import 'package:quark/utils/thumbnail_cache_config.dart';

/// Builds a Quark thumbnail and, when it fails to load, asks
/// [ThumbnailBackfill] to render and upload it (#2381), then builds it again.
///
/// App-side because it calls a service. [builder] draws the thumbnail: it gets
/// a `generation` to key its image with, so the reload after a backfill is a
/// new element that fetches afresh, and an `onFailed` to call from its error
/// state, with the error when it has one. The generation stays out of the
/// image's cache key, which has to outlive the session (#1777).
/// Only a tile that is built — one on screen — ever asks, and it asks once.
///
/// A load the Quark turned away for being busy (a 429, 502, 503 or 504) is
/// not a missing thumbnail: it is built again after
/// [ThumbnailCacheConfig.busyRetryDelay], a few times, rather than left on
/// its placeholder until it is scrolled away and back (#3349).
///
/// ```dart
/// BackfillingThumbnail(
///   path: node.apiPath,
///   serial: node.deviceSerial,
///   builder: (context, generation, onFailed) => CachedNetworkImage(
///     key: ValueKey(generation),
///     imageUrl: url.toString(),
///     cacheKey: ThumbnailCacheManager.keyFor(url),
///     cacheManager: ThumbnailCacheManager.instance,
///     errorWidget: (context, url, error) {
///       onFailed(error);
///       return icon;
///     },
///   ),
/// )
/// ```
class BackfillingThumbnail extends StatefulWidget {
  /// Creates the thumbnail of the file at [path] on the device [serial].
  const BackfillingThumbnail({
    required this.path,
    required this.builder,
    this.serial,
    this.backfill,
    super.key,
  });

  /// The file's path, as the Quark's API addresses it.
  final String path;

  /// The device the file is on, empty or null for the internal one.
  final String? serial;

  /// Draws the thumbnail. See the class doc for its arguments.
  final Widget Function(
    BuildContext context,
    int generation,
    void Function([Object? error]) onFailed,
  )
  builder;

  /// The backfill to ask; [ThumbnailBackfill.instance] when null.
  final ThumbnailBackfill? backfill;

  @override
  State<BackfillingThumbnail> createState() => _BackfillingThumbnailState();
}

class _BackfillingThumbnailState extends State<BackfillingThumbnail> {
  /// The statuses a Quark answers with when it is busy rather than when the
  /// thumbnail is missing.
  static const _busy = {429, 502, 503, 504};

  int _generation = 0;
  bool _asked = false;
  int _retries = 0;
  Timer? _retry;

  @override
  void didUpdateWidget(BackfillingThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.serial != widget.serial) {
      _generation = 0;
      _asked = false;
      _retries = 0;
      _retry?.cancel();
      _retry = null;
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  // Called from the builder's error state, during a build: it starts the
  // work and only touches state once the work is done.
  void _onFailed([Object? error]) {
    if (error is HttpExceptionWithStatus && _busy.contains(error.statusCode)) {
      if (_retry != null || _retries >= ThumbnailCacheConfig.busyRetries) {
        return;
      }
      _retry = Timer(ThumbnailCacheConfig.busyRetryDelay * (1 << _retries), () {
        _retry = null;
        _retries++;
        if (mounted) setState(() => _generation++);
      });
      return;
    }
    if (_asked) return;
    _asked = true;
    final path = widget.path;
    final serial = widget.serial;
    unawaited(
      (widget.backfill ?? ThumbnailBackfill.instance)
          .fill(path: path, serial: serial, stillWanted: () => mounted)
          .then((filled) {
            if (!filled || !mounted) return;
            if (widget.path != path || widget.serial != serial) return;
            setState(() => _generation++);
          }),
    );
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _generation, _onFailed);
}
