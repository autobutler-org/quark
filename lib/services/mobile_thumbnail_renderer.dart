import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress_common/flutter_image_compress_common.dart';
import 'package:flutter_image_compress_platform_interface/flutter_image_compress_platform_interface.dart';
import 'package:quark/utils/client_thumbnail_config.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// The platform calls the iOS and Android thumbnail renderer makes, one field
/// each, so a test can swap them for fakes.
class MobileThumbnailCodecs {
  const MobileThumbnailCodecs({
    required this.videoFrame,
    required this.videoDuration,
    required this.sourceSizeOfFile,
    required this.sizeOfBytes,
    required this.compressFile,
    required this.compressBytes,
  });

  /// A JPEG of the video at [path] (a file path or an http(s) URL) at [at],
  /// fit within a [longEdge] square.
  final Future<Uint8List?> Function(
    String path, {
    required int longEdge,
    required Duration at,
  })
  videoFrame;

  /// The length of the video at [path] (a file path or an http(s) URL), or
  /// null when it cannot be read.
  final Future<Duration?> Function(String path) videoDuration;

  /// The pixel size of the image file at [path], read from its header, or
  /// null when Flutter cannot read it (HEIC on some platforms).
  final Future<({int width, int height})?> Function(String path)
  sourceSizeOfFile;

  /// The pixel size of an encoded image, or null when it cannot be read.
  final Future<({int width, int height})?> Function(Uint8List bytes)
  sizeOfBytes;

  /// A JPEG of the image at [path], EXIF rotation applied, scaled down so its
  /// shorter side is [shortEdge] and never enlarged.
  final Future<Uint8List?> Function(String path, {required int shortEdge})
  compressFile;

  /// The same for an image already in memory.
  final Future<Uint8List?> Function(Uint8List bytes, {required int shortEdge})
  compressBytes;

  /// The real calls: `video_thumbnail` for frames (AVAssetImageGenerator,
  /// MediaMetadataRetriever), `flutter_image_compress` for photos and HEIC,
  /// `video_player` for a video's length, and the engine for image sizes.
  static final MobileThumbnailCodecs platform = MobileThumbnailCodecs(
    videoFrame: _videoFrame,
    videoDuration: _videoDuration,
    sourceSizeOfFile: _sizeOfFile,
    sizeOfBytes: _sizeOfBytes,
    compressFile: _compressFile,
    compressBytes: _compressBytes,
  );
}

/// Renders the thumbnail of the file [name] (a JPEG, long edge 400, rotation
/// applied) from its [path], or from its [bytes] when there is no path
/// (#2379). A video needs a path; from bytes alone it renders nothing.
///
/// Returns null rather than throwing, and gives up after [timeout]: the file
/// uploads either way.
Future<Uint8List?> renderMobileThumbnail({
  required String name,
  String? path,
  Uint8List? bytes,
  MobileThumbnailCodecs? codecs,
  Duration timeout = ClientThumbnailConfig.renderTimeout,
}) async {
  if (!wantsClientThumbnail(name) || (path == null && bytes == null)) {
    return null;
  }
  final use = codecs ?? MobileThumbnailCodecs.platform;
  try {
    final Future<Uint8List?> render;
    if (fileKindForName(name) == FileKind.video) {
      if (path == null) return null;
      render = _renderVideo(use, path);
    } else {
      render = _renderImage(use, path: path, bytes: bytes);
    }
    return await render.timeout(timeout);
  } catch (e) {
    debugPrint('[mobile_thumbnail_renderer.dart] No thumbnail for $name: $e');
    return null;
  }
}

/// Renders the thumbnail of the video [name] streamed from [url] (#2381).
/// The platform reads only what the frame needs, through range requests.
Future<Uint8List?> renderMobileVideoThumbnailFromUrl({
  required String name,
  required Uri url,
  MobileThumbnailCodecs? codecs,
  Duration timeout = ClientThumbnailConfig.renderTimeout,
}) async {
  if (fileKindForName(name) != FileKind.video) return null;
  try {
    return await _renderVideo(
      codecs ?? MobileThumbnailCodecs.platform,
      url.toString(),
    ).timeout(timeout);
  } catch (e) {
    debugPrint('[mobile_thumbnail_renderer.dart] No thumbnail for $name: $e');
    return null;
  }
}

Future<Uint8List?> _renderVideo(
  MobileThumbnailCodecs codecs,
  String path,
) async {
  final duration = await codecs.videoDuration(path);
  // Without a length, two seconds in is the Quark's rule for anything long
  // enough to have a frame there.
  final at = duration == null
      ? ClientThumbnailConfig.videoFrameAt
      : videoFrameTime(duration);
  return codecs.videoFrame(
    path,
    longEdge: ClientThumbnailConfig.longEdge,
    at: at,
  );
}

Future<Uint8List?> _renderImage(
  MobileThumbnailCodecs codecs, {
  String? path,
  Uint8List? bytes,
}) async {
  const longEdge = ClientThumbnailConfig.longEdge;
  final source = path != null
      ? await codecs.sourceSizeOfFile(path)
      : await codecs.sizeOfBytes(bytes!);
  // The plugin scales so the shorter side lands on what it is given, and
  // never enlarges. Asking for the short side of the target size puts the
  // long side on [longEdge]; with the source size unknown, the first pass
  // only bounds the short side and a second, on the small JPEG it made,
  // finishes the job.
  final firstShort = source == null
      ? longEdge
      : _shortSide(scaledToLongEdge(source.width, source.height, longEdge));
  final first = path != null
      ? await codecs.compressFile(path, shortEdge: firstShort)
      : await codecs.compressBytes(bytes!, shortEdge: firstShort);
  if (first == null) return null;
  final size = await codecs.sizeOfBytes(first);
  if (size == null || math.max(size.width, size.height) <= longEdge) {
    return first;
  }
  return codecs.compressBytes(
    first,
    shortEdge: _shortSide(scaledToLongEdge(size.width, size.height, longEdge)),
  );
}

int _shortSide(({int width, int height}) size) =>
    math.min(size.width, size.height);

int get _jpegQuality => (ClientThumbnailConfig.jpegQuality * 100).round();

final _compressor = FlutterImageCompressCommon();

Future<Uint8List?> _compressFile(String path, {required int shortEdge}) {
  return _compressor.compressWithFile(
    path,
    minWidth: shortEdge,
    minHeight: shortEdge,
    quality: _jpegQuality,
    // Rotate by the EXIF orientation, then drop EXIF so nothing rotates the
    // result a second time.
    autoCorrectionAngle: true,
    keepExif: false,
    format: CompressFormat.jpeg,
  );
}

Future<Uint8List?> _compressBytes(Uint8List bytes, {required int shortEdge}) {
  return _compressor.compressWithList(
    bytes,
    minWidth: shortEdge,
    minHeight: shortEdge,
    quality: _jpegQuality,
    autoCorrectionAngle: true,
    keepExif: false,
    format: CompressFormat.jpeg,
  );
}

Future<Uint8List?> _videoFrame(
  String path, {
  required int longEdge,
  required Duration at,
}) {
  return VideoThumbnail.thumbnailData(
    video: path,
    imageFormat: ImageFormat.JPEG,
    maxWidth: longEdge,
    maxHeight: longEdge,
    timeMs: at.inMilliseconds,
    quality: _jpegQuality,
  );
}

Future<Duration?> _videoDuration(String path) async {
  final controller = path.startsWith('http')
      ? VideoPlayerController.networkUrl(Uri.parse(path))
      : VideoPlayerController.file(File(path));
  try {
    await controller.initialize();
    final duration = controller.value.duration;
    return duration == Duration.zero ? null : duration;
  } catch (_) {
    return null;
  } finally {
    await controller.dispose();
  }
}

Future<({int width, int height})?> _sizeOfFile(String path) async {
  try {
    return await _sizeOf(await ui.ImmutableBuffer.fromFilePath(path));
  } catch (_) {
    return null;
  }
}

Future<({int width, int height})?> _sizeOfBytes(Uint8List bytes) async {
  try {
    return await _sizeOf(await ui.ImmutableBuffer.fromUint8List(bytes));
  } catch (_) {
    return null;
  }
}

/// Reads the size from the image header; the pixels are never decoded.
Future<({int width, int height})> _sizeOf(ui.ImmutableBuffer buffer) async {
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = (width: descriptor.width, height: descriptor.height);
    descriptor.dispose();
    return size;
  } finally {
    buffer.dispose();
  }
}
