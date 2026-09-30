import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

/// iOS and Android: captures the `RepaintBoundary` under [frameKey], where
/// the player's texture is composited, scaled up or down to the video's own
/// resolution. Before the video reports a size, the frame is taken at the
/// size it is shown.
Future<Uint8List> captureVideoFramePlatform(
  VideoPlayerController controller,
  GlobalKey frameKey,
) async {
  final boundary = frameKey.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary || boundary.size.isEmpty) {
    throw Exception('The video is not on screen to grab a frame from');
  }
  final video = controller.value.size;
  final shown = boundary.size;
  // The longer sides are compared so a rotated video still scales right.
  final pixelRatio = video.isEmpty
      ? 1.0
      : math.max(video.width, video.height) /
            math.max(shown.width, shown.height);
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw Exception('The frame could not be encoded');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
