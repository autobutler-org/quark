import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:video_player/video_player.dart';

/// The photo on screen: the Live Photo video while it plays, otherwise the
/// rotatable, zoomable still, labeled with [name] for screen readers.
class CurrentPhoto extends StatelessWidget {
  final Uint8List bytes;
  final String name;
  final Animation<double> rotation;
  final TransformationController zoomController;
  final bool zoomedIn;
  final bool liveVideoPlaying;
  final VideoPlayerController? liveVideoController;

  const CurrentPhoto({
    super.key,
    required this.bytes,
    required this.name,
    required this.rotation,
    required this.zoomController,
    required this.zoomedIn,
    required this.liveVideoPlaying,
    required this.liveVideoController,
  });

  /// Pixel width to decode the photo at, or null for its full resolution.
  ///
  /// A phone photo is several times wider than the screen showing it, and
  /// decoding one at full sensor resolution costs both the decode and ~48MB of
  /// RGBA held for a frame nobody can see the detail in. Same bytes off the
  /// network either way — this is free speed (#1710).
  ///
  /// The *larger* viewport side is used because `BoxFit.contain` may add a
  /// letterbox on either axis and `Transform.rotate` may have turned the
  /// photo a quarter turn, so the smaller side is not a safe bound. Zoomed in,
  /// the downscaled decode is no longer enough and the full-resolution one is
  /// what the user pinched for.
  int? _decodeWidth(BuildContext context, BoxConstraints constraints) {
    if (zoomedIn) return null;
    final side = math.max(constraints.maxWidth, constraints.maxHeight);
    if (!side.isFinite || side <= 0) return null;
    return (side * MediaQuery.devicePixelRatioOf(context)).round();
  }

  @override
  Widget build(BuildContext context) {
    if (liveVideoPlaying && liveVideoController != null) {
      return AspectRatio(
        aspectRatio: liveVideoController!.value.aspectRatio.clamp(0.1, 10.0),
        child: VideoPlayer(liveVideoController!),
      );
    }
    return AnimatedBuilder(
      animation: rotation,
      builder: (_, child) =>
          Transform.rotate(angle: rotation.value, child: child),
      child: InteractiveViewer(
        transformationController: zoomController,
        child: LayoutBuilder(
          builder: (context, constraints) => Image.memory(
            bytes,
            semanticLabel: name,
            fit: BoxFit.contain,
            cacheWidth: _decodeWidth(context, constraints),
            // Keep the downscaled frame on screen while the full-resolution
            // one decodes, so starting a pinch doesn't blank the photo.
            gaplessPlayback: true,
            errorBuilder: (context, error, stack) => const Icon(
              QuarkIcons.broken_image,
              size: 64,
              color: Colors.white54,
            ),
          ),
        ),
      ),
    );
  }
}
