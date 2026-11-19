import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:quark/utils/client_thumbnail_config.dart';
import 'package:quark/utils/file_kind.dart';

/// The platform calls the desktop video thumbnail renderer makes, one field
/// each, so a test can swap them for fakes.
class DesktopThumbnailCodecs {
  const DesktopThumbnailCodecs({
    required this.videoDuration,
    required this.videoFrame,
  });

  /// The length of the video at [source] (a file path or an http(s) URL), or
  /// null when it cannot be read.
  final Future<Duration?> Function(String source) videoDuration;

  /// A JPEG of the video at [source] at [at], fit within a [longEdge] square.
  final Future<Uint8List?> Function(
    String source, {
    required int longEdge,
    required Duration at,
  })
  videoFrame;

  /// The real calls, through libmpv: the player the Linux app already plays
  /// video with (`installVideoPlaybackBackend`), so it decodes whatever the
  /// viewer can play and the Quark never has to (#2378).
  static const DesktopThumbnailCodecs platform = DesktopThumbnailCodecs(
    videoDuration: _videoDuration,
    videoFrame: _videoFrame,
  );
}

/// Renders the thumbnail of the video [name] at [source] (a file path or an
/// http(s) URL) with the desktop player, a JPEG with a long edge of 400
/// (#3421). Anything but a video renders nothing.
///
/// Returns null rather than throwing, and gives up after [timeout]: the file
/// uploads either way, without a thumbnail, as from an older client.
Future<Uint8List?> renderDesktopVideoThumbnail({
  required String name,
  required String source,
  DesktopThumbnailCodecs codecs = DesktopThumbnailCodecs.platform,
  Duration timeout = ClientThumbnailConfig.renderTimeout,
}) async {
  if (fileKindForName(name) != FileKind.video) return null;
  try {
    return await _render(codecs, source).timeout(timeout);
  } catch (e) {
    debugPrint('[desktop_thumbnail_renderer.dart] No thumbnail for $name: $e');
    return null;
  }
}

Future<Uint8List?> _render(DesktopThumbnailCodecs codecs, String source) async {
  final duration = await codecs.videoDuration(source);
  final at = duration == null
      ? ClientThumbnailConfig.videoFrameAt
      : videoFrameTime(duration);
  return codecs.videoFrame(
    source,
    longEdge: ClientThumbnailConfig.longEdge,
    at: at,
  );
}

/// Opens [source] paused in a player with no video output and waits for its
/// length to be known.
Future<Player> _open(String source) async {
  final player = Player();
  try {
    await player.open(Media(source), play: false);
    await player.stream.duration.firstWhere((d) => d > Duration.zero);
    return player;
  } catch (_) {
    await player.dispose();
    rethrow;
  }
}

Future<Duration?> _videoDuration(String source) async {
  final player = await _open(source);
  try {
    return player.state.duration;
  } finally {
    await player.dispose();
  }
}

Future<Uint8List?> _videoFrame(
  String source, {
  required int longEdge,
  required Duration at,
}) async {
  final player = await _open(source);
  try {
    // libmpv scales the frame, and applies the video's rotation, before the
    // screenshot is taken.
    await (player.platform as NativePlayer).setProperty(
      'vf',
      'scale=w=$longEdge:h=$longEdge:force_original_aspect_ratio=decrease',
    );
    await player.seek(at);
    await player.stream.position.firstWhere((p) => p >= at);
    return await player.screenshot(format: 'image/jpeg');
  } finally {
    await player.dispose();
  }
}
