import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:quark/utils/video_frame_capture_io.dart'
    if (dart.library.js_interop) 'package:quark/utils/video_frame_capture_web.dart';
import 'package:video_player/video_player.dart';

/// Grabs the frame [controller] is showing as PNG bytes, on the device doing
/// the playing: the Quark never decodes video (#2380).
///
/// On iOS and Android the player draws into a texture, and [frameKey] is the
/// `RepaintBoundary` around it, rasterized at the video's own resolution. On
/// the web the player is a `<video>` element, drawn onto a canvas.
Future<Uint8List> captureVideoFrame(
  VideoPlayerController controller,
  GlobalKey frameKey,
) => captureVideoFramePlatform(controller, frameKey);

/// The file name a frame of [videoName] taken at [position] is saved under:
/// `clip.mp4` at 2.5s is `clip_frame_0m02s.png`.
String videoFrameFileName(String videoName, Duration position) {
  final dot = videoName.lastIndexOf('.');
  final stem = dot > 0 ? videoName.substring(0, dot) : videoName;
  final h = position.inHours;
  final m = position.inMinutes.remainder(60);
  final s = position.inSeconds.remainder(60).toString().padLeft(2, '0');
  final label = h > 0
      ? '${h}h${m.toString().padLeft(2, '0')}m${s}s'
      : '${m}m${s}s';
  return '${stem}_frame_$label.png';
}
