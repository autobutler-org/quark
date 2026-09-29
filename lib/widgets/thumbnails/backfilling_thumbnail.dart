import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:quark/services/thumbnail_backfill.dart';

/// Builds a Quark thumbnail and, when it fails to load, asks
/// [ThumbnailBackfill] to render and upload it (#2381), then builds it again.
///
/// App-side because it calls a service. [builder] draws the thumbnail: it gets
/// a `generation` to fold into its image cache key, so the reload after a
/// backfill fetches afresh, and an `onFailed` to call from its error state.
/// Only a tile that is built — one on screen — ever asks, and it asks once.
///
/// ```dart
/// BackfillingThumbnail(
///   path: node.apiPath,
///   serial: node.deviceSerial,
///   builder: (context, generation, onFailed) => CachedNetworkImage(
///     imageUrl: url,
///     cacheKey: '$url#$generation',
///     errorWidget: (context, url, error) {
///       onFailed();
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
    VoidCallback onFailed,
  )
  builder;

  /// The backfill to ask; [ThumbnailBackfill.instance] when null.
  final ThumbnailBackfill? backfill;

  @override
  State<BackfillingThumbnail> createState() => _BackfillingThumbnailState();
}

class _BackfillingThumbnailState extends State<BackfillingThumbnail> {
  int _generation = 0;
  bool _asked = false;

  @override
  void didUpdateWidget(BackfillingThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.serial != widget.serial) {
      _generation = 0;
      _asked = false;
    }
  }

  // Called from the builder's error state, during a build: it starts the
  // work and only touches state once the work is done.
  void _onFailed() {
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
