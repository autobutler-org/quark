import 'dart:async';
import 'dart:js_interop';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:quark/utils/client_thumbnail_config.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:web/web.dart' as web;

/// Renders the thumbnail of [blob], the file [name], with the browser's
/// decoders: `createImageBitmap` for a photo, which applies its EXIF
/// orientation, and a `<video>` element seeked to the Quark's frame for a
/// video. A format the browser cannot decode — HEIC outside Safari, HEVC in
/// most of them — renders nothing.
Future<Uint8List?> renderBlobThumbnail(web.Blob blob, String name) async {
  if (!wantsClientThumbnail(name)) {
    return null;
  }
  try {
    final render = fileKindForName(name) == FileKind.video
        ? _renderVideo(blob)
        : _renderImage(blob);
    return await render.timeout(ClientThumbnailConfig.renderTimeout);
  } catch (e) {
    debugPrint('[client_thumbnails_web.dart] No thumbnail for $name: $e');
    return null;
  }
}

Future<Uint8List?> renderThumbnailFromBytesPlatform(
  String name,
  Uint8List bytes,
) {
  return renderBlobThumbnail(web.Blob([bytes.toJS].toJS), name);
}

Future<Uint8List?> renderDroppedFileThumbnailPlatform(DropItemFile file) async {
  if (!wantsClientThumbnail(file.name) || file.path.isEmpty) {
    return null;
  }
  try {
    // The dropped item is an object URL for a Blob the browser already holds;
    // fetching it hands back that Blob, not a copy of its bytes.
    final response = await web.window.fetch(file.path.toJS).toDart;
    return await renderBlobThumbnail(await response.blob().toDart, file.name);
  } catch (e) {
    debugPrint('[client_thumbnails_web.dart] Cannot open ${file.name}: $e');
    return null;
  }
}

Future<Uint8List> _renderImage(web.Blob blob) async {
  final bitmap = await web.window.createImageBitmap(blob).toDart;
  try {
    return await _encodeJpeg(bitmap, bitmap.width, bitmap.height);
  } finally {
    bitmap.close();
  }
}

Future<Uint8List?> _renderVideo(web.Blob blob) async {
  final url = web.URL.createObjectURL(blob);
  final video = web.HTMLVideoElement()
    ..muted = true
    ..preload = 'auto'
    ..playsInline = true;
  try {
    video.src = url;
    await _next(video, 'loadedmetadata');
    final seconds = video.duration;
    final duration = seconds.isFinite
        ? Duration(milliseconds: (seconds * 1000).round())
        : ClientThumbnailConfig.shortVideo;
    video.currentTime = videoFrameTime(duration).inMilliseconds / 1000;
    await _next(video, 'seeked');

    final width = video.videoWidth;
    final height = video.videoHeight;
    if (width == 0 || height == 0) {
      // Audio only, or a container the browser opens but cannot decode.
      return null;
    }
    return await _encodeJpeg(video, width, height);
  } finally {
    // Drop the element's hold on the Blob before the URL goes.
    video.removeAttribute('src');
    video.load();
    web.URL.revokeObjectURL(url);
  }
}

/// Completes when [video] fires [event], or fails when it fires `error`.
Future<void> _next(web.HTMLVideoElement video, String event) {
  final completer = Completer<void>();
  late final JSFunction onEvent;
  late final JSFunction onError;
  void detach() {
    video.removeEventListener(event, onEvent);
    video.removeEventListener('error', onError);
  }

  onEvent = ((web.Event _) {
    detach();
    if (!completer.isCompleted) completer.complete();
  }).toJS;
  onError = ((web.Event _) {
    detach();
    if (!completer.isCompleted) {
      completer.completeError(
        Exception(
          'the browser cannot decode this video (${video.error?.code})',
        ),
      );
    }
  }).toJS;
  video.addEventListener(event, onEvent);
  video.addEventListener('error', onError);
  return completer.future;
}

/// Draws [source], [width] x [height], scaled to the thumbnail's long edge
/// and encoded as JPEG by the browser.
Future<Uint8List> _encodeJpeg(
  web.CanvasImageSource source,
  int width,
  int height,
) async {
  final size = scaledToLongEdge(width, height, ClientThumbnailConfig.longEdge);
  final canvas = web.HTMLCanvasElement()
    ..width = size.width
    ..height = size.height;
  final context = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
  context.drawImage(source, 0, 0, size.width, size.height);

  final encoded = Completer<web.Blob?>();
  canvas.toBlob(
    ((web.Blob? blob) => encoded.complete(blob)).toJS,
    'image/jpeg',
    ClientThumbnailConfig.jpegQuality.toJS,
  );
  final jpeg = await encoded.future;
  if (jpeg == null) {
    throw Exception('the browser would not encode a JPEG');
  }
  final buffer = await jpeg.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}
