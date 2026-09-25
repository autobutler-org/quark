import 'dart:math' as math;

import 'package:quark/utils/file_kind.dart';

/// Sizes and timing for the thumbnails and previews a client renders at
/// upload (#2379), and the small rules that go with them.
abstract final class DerivativeConfig {
  /// Long edge of the thumbnail. The Quark serves 96, 240 and 400 and resizes
  /// the smaller two from this, so it is the largest of them.
  static const int thumbnailLongEdge = 400;

  /// Long edge of the display preview shown in place of a HEIC or a video
  /// poster: sharp on a phone or a laptop screen, a few hundred KB as JPEG.
  static const int previewLongEdge = 2048;

  /// JPEG quality for both, as the 0–1 the browser's encoder takes.
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

/// Whether [name] gets a display preview as well as a thumbnail: a HEIC,
/// which most clients cannot show at full size, or a video, whose preview is
/// its poster frame.
bool wantsDisplayPreview(String name) {
  final ext = fileExtension(name);
  return ext == '.heic' ||
      ext == '.heif' ||
      fileKindForName(name) == FileKind.video;
}

/// Whether the client renders derivatives for [name] at all: every photo and
/// every video. A browser that cannot decode one simply renders nothing.
bool wantsDerivatives(String name) {
  final kind = fileKindForName(name);
  return kind == FileKind.image || kind == FileKind.video;
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
  if (duration < DerivativeConfig.shortVideo) {
    return duration ~/ 10;
  }
  return DerivativeConfig.videoFrameAt;
}
