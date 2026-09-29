import 'dart:math' as math;

import 'package:quark/utils/file_kind.dart';

/// Size and timing for the thumbnails a client renders for the photos and
/// videos it uploads (#2379), and the small rules that go with them.
abstract final class ClientThumbnailConfig {
  /// Long edge of the thumbnail. The Quark serves 96, 240 and 400 and resizes
  /// all three from this, so it is the largest of them.
  static const int longEdge = 400;

  /// JPEG quality, as the 0–1 the browser's encoder takes.
  static const double jpegQuality = 0.85;

  /// How far into a video its frame is taken, matching the Quark's own rule.
  static const Duration videoFrameAt = Duration(seconds: 2);

  /// Below this length a video's frame is a tenth of the way in instead, so a
  /// short clip does not land on its last frame or past it.
  static const Duration shortVideo = Duration(seconds: 20);

  /// How long rendering one file may take before it is skipped. The file
  /// still uploads; it goes without a thumbnail, as from an older client.
  static const Duration renderTimeout = Duration(seconds: 20);
}

/// Whether the client renders a thumbnail for [name]: every photo and every
/// video. A platform that cannot decode one simply renders nothing.
bool wantsClientThumbnail(String name) {
  final kind = fileKindForName(name);
  return kind == FileKind.image || kind == FileKind.video;
}

/// Whether [name] is a file only a client can make a thumbnail for: a video,
/// whose H.264 and HEVC frames the Quark does not decode, or a HEIC. The
/// Quark marks a missing thumbnail for these with `clientRender` (#2381).
bool needsClientRender(String name) {
  final ext = fileExtension(name);
  return ext == '.heic' ||
      ext == '.heif' ||
      fileKindForName(name) == FileKind.video;
}

/// The size of a [width] x [height] image scaled so its long edge is at most
/// [longEdge], never enlarged, and never below one pixel on a side.
({int width, int height}) scaledToLongEdge(
  int width,
  int height,
  int longEdge,
) {
  final long = math.max(width, height);
  if (long <= longEdge || long == 0) {
    return (width: width, height: height);
  }
  final scale = longEdge / long;
  return (
    width: math.max(1, (width * scale).round()),
    height: math.max(1, (height * scale).round()),
  );
}

/// Where in a video of [duration] its thumbnail frame is taken: two seconds
/// in, or a tenth of the way through a clip shorter than twenty seconds.
Duration videoFrameTime(Duration duration) {
  if (duration < ClientThumbnailConfig.shortVideo) {
    return duration ~/ 10;
  }
  return ClientThumbnailConfig.videoFrameAt;
}
