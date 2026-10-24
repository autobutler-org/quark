import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:quark/services/thumbnail_backfill.dart';
import 'package:quark/utils/thumbnail_cache_config.dart';
import 'package:quark_widgets/quark_widgets.dart' show ThumbnailIssue;

/// Builds a Quark thumbnail and, when it fails to load, asks
/// [ThumbnailBackfill] to render and upload it (#2381), then builds it again.
///
/// App-side because it calls a service. [builder] draws the thumbnail: it gets
/// a `generation` to key its image with, so the reload after a backfill is a
/// new element that fetches afresh, and an `onFailed` to call from its error
/// state, with the error when it has one. `onFailed` answers whether the
/// thumbnail may still arrive — a retry is due or a backfill is running — so
/// the error state can tell waiting from giving up (#3509). The generation
/// stays out of the image's cache key, which has to outlive the session
/// (#1777).
/// Only a tile that is built — one on screen — ever asks, and it asks once.
///
/// A load the Quark turned away for being busy (a 429, 502, 503 or 504) is
/// not a missing thumbnail: it is built again after
/// [ThumbnailCacheConfig.busyRetryDelay], a few times, rather than left on
/// its placeholder until it is scrolled away and back (#3349).
///
/// A backfill that could not render the thumbnail either builds
/// [failedBuilder] instead, with why, so the tile says it will have no
/// thumbnail rather than look like a file that never has one (#3559). It is
/// only built after this tile's own load failed, so a thumbnail that has
/// appeared since shows.
///
/// ```dart
/// BackfillingThumbnail(
///   path: node.apiPath,
///   serial: node.deviceSerial,
///   builder: (context, generation, onFailed) => Image(
///     key: ValueKey(generation),
///     image: ThumbnailCacheManager.image(url),
///     errorBuilder: (context, error, stack) {
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
    this.failedBuilder,
    this.issueFor,
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
    bool Function([Object? error]) onFailed,
  )
  builder;

  /// Draws the tile when no thumbnail could be rendered, with why. Null keeps
  /// [builder]'s error state.
  final Widget Function(BuildContext context, ThumbnailIssue issue)?
  failedBuilder;

  /// Reads why a load failed for good from its error, for a backfill that
  /// answered without a thumbnail or a reason of its own: [failedBuilder] is
  /// built with it, rather than [builder] again, whose image would fetch
  /// afresh (#3509). Null leaves [builder]'s error state.
  final ThumbnailIssue Function(Object? error)? issueFor;

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

  /// Whether the backfill this tile asked has yet to answer.
  bool _filling = false;

  /// What the load that asked the backfill failed with.
  Object? _error;

  /// Why the backfill could not render this file, once it has said.
  ThumbnailIssue? _issue;
  int _retries = 0;
  Timer? _retry;

  @override
  void didUpdateWidget(BackfillingThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.serial != widget.serial) {
      _generation = 0;
      _asked = false;
      _filling = false;
      _error = null;
      _issue = null;
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
  bool _onFailed([Object? error]) {
    if (error is HttpExceptionWithStatus && _busy.contains(error.statusCode)) {
      if (_retry == null && _retries < ThumbnailCacheConfig.busyRetries) {
        _retry = Timer(
          ThumbnailCacheConfig.busyRetryDelay * (1 << _retries),
          () {
            _retry = null;
            _retries++;
            if (mounted) setState(() => _generation++);
          },
        );
      }
      return _retry != null;
    }
    if (_asked) return _filling;
    _asked = true;
    _filling = true;
    _error = error;
    final path = widget.path;
    final serial = widget.serial;
    final backfill = widget.backfill ?? ThumbnailBackfill.instance;
    unawaited(
      backfill
          .fill(path: path, serial: serial, stillWanted: () => mounted)
          .then((filled) {
            if (!mounted) return;
            if (widget.path != path || widget.serial != serial) return;
            _filling = false;
            final issue = filled
                ? null
                : backfill.failureFor(path, serial: serial) ??
                      widget.issueFor?.call(_error);
            if (!filled && issue == null) return;
            setState(() {
              if (filled) {
                _generation++;
              } else {
                _issue = issue;
              }
            });
          }),
    );
    return _filling;
  }

  @override
  Widget build(BuildContext context) {
    final failed = widget.failedBuilder;
    final issue = _issue;
    return failed != null && issue != null
        ? failed(context, issue)
        : widget.builder(context, _generation, _onFailed);
  }
}
