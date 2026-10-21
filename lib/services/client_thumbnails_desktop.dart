import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/utils/client_thumbnail_config.dart';
import 'package:quark/utils/file_kind.dart';

/// One video opened on the desktop player, from which the frame can be taken.
abstract interface class DesktopVideoSession {
  /// The length of the video, or null when the player does not report one.
  Future<Duration?> get duration;

  /// A JPEG of the video at [at], fit within a [longEdge] square, or null
  /// when the player cannot decode a frame there.
  Future<Uint8List?> frameAt(Duration at, {required int longEdge});

  /// Releases the player and anything it holds open.
  Future<void> close();
}

/// Opens [source], a file path or an http(s) URL, on the desktop player.
typedef OpenDesktopVideo = Future<DesktopVideoSession> Function(String source);

/// Renders the thumbnail of the video [name] at [source], on the player the
/// desktop app embeds for playback (#3421), so the Quark never has to decode
/// the video itself. The frame is the Quark's own pick, [videoFrameTime].
///
/// Returns null rather than throwing, and gives up after [timeout]: anything
/// but a video, a codec the player cannot decode, or a file that never opens
/// uploads without a thumbnail, as from an older client.
Future<Uint8List?> renderDesktopVideoThumbnail({
  required String name,
  required String source,
  required OpenDesktopVideo open,
  Duration timeout = ClientThumbnailConfig.renderTimeout,
}) async {
  if (fileKindForName(name) != FileKind.video) return null;
  try {
    return await _render(open, source).timeout(timeout);
  } catch (e) {
    debugPrint('[client_thumbnails_desktop.dart] No thumbnail for $name: $e');
    return null;
  }
}

Future<Uint8List?> _render(OpenDesktopVideo open, String source) async {
  final session = await open(source);
  try {
    final duration = await session.duration;
    // Without a length, two seconds in is the Quark's rule for anything long
    // enough to have a frame there.
    final at = duration == null
        ? ClientThumbnailConfig.videoFrameAt
        : videoFrameTime(duration);
    return await session.frameAt(at, longEdge: ClientThumbnailConfig.longEdge);
  } finally {
    await session.close();
  }
}
