import 'dart:async';
import 'dart:js_interop';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:quark/models/upload_derivatives.dart';
import 'package:quark/utils/derivative_config.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:web/web.dart' as web;

/// Renders derivatives for [blob], the file [name], with the browser's
/// decoders: `createImageBitmap` for a photo, which applies its EXIF
/// orientation, and a `<video>` element seeked to the Quark's frame for a
/// video. A format the browser cannot decode — HEIC outside Safari, HEVC in
/// most of them — renders nothing.
Future<UploadDerivatives?> renderBlobDerivatives(
  web.Blob blob,
  String name,
) async {
  if (!wantsDerivatives(name)) {
    return null;
  }
  try {
    final preview = wantsDisplayPreview(name);
    final render = fileKindForName(name) == FileKind.video
        ? _renderVideo(blob, preview: preview)
        : _renderImage(blob, preview: preview);
    return await render.timeout(DerivativeConfig.renderTimeout);
  } catch (e) {
    debugPrint('[media_derivatives_web.dart] No derivatives for $name: $e');
    return null;
  }
}

Future<UploadDerivatives?> renderDerivativesFromBytesPlatform(
  String name,
  Uint8List bytes,
) {
  return renderBlobDerivatives(web.Blob([bytes.toJS].toJS), name);
}

Future<UploadDerivatives?> renderDroppedFileDerivativesPlatform(
  DropItemFile file,
) async {
  if (!wantsDerivatives(file.name) || file.path.isEmpty) {
    return null;
  }
  try {
    // The dropped item is an object URL for a Blob the browser already holds;
    // fetching it hands back that Blob, not a copy of its bytes.
    final response = await web.window.fetch(file.path.toJS).toDart;
    return await renderBlobDerivatives(await response.blob().toDart, file.name);
  } catch (e) {
    debugPrint('[media_derivatives_web.dart] Cannot open ${file.name}: $e');
    return null;
  }
}

Future<UploadDerivatives> _renderImage(
  web.Blob blob, {
  required bool preview,
}) async {
  final bitmap = await web.window.createImageBitmap(blob).toDart;
  try {
    return UploadDerivatives(
      thumbnail: await _encodeJpeg(
        bitmap,
        bitmap.width,
        bitmap.height,
        DerivativeConfig.thumbnailLongEdge,
      ),
      preview: preview
          ? await _encodeJpeg(
              bitmap,
              bitmap.width,
              bitmap.height,
              DerivativeConfig.previewLongEdge,
            )
          : null,
    );
  } finally {
    bitmap.close();
  }
}

Future<UploadDerivatives?> _renderVideo(
  web.Blob blob, {
  required bool preview,
}) async {
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
        : DerivativeConfig.shortVideo;
    video.currentTime = videoFrameTime(duration).inMilliseconds / 1000;
    await _next(video, 'seeked');

    final width = video.videoWidth;
    final height = video.videoHeight;
    if (width == 0 || height == 0) {
      // Audio only, or a container the browser opens but cannot decode.
      return null;
    }
    return UploadDerivatives(
      thumbnail: await _encodeJpeg(
        video,
        width,
        height,
        DerivativeConfig.thumbnailLongEdge,
      ),
      preview: preview
          ? await _encodeJpeg(
              video,
              width,
              height,
              DerivativeConfig.previewLongEdge,
            )
          : null,
    );
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

/// Draws [source], [width] x [height], scaled to [longEdge] and encoded as
/// JPEG by the browser.
Future<Uint8List> _encodeJpeg(
  web.CanvasImageSource source,
  int width,
  int height,
  int longEdge,
) async {
  final size = scaledToLongEdge(width, height, longEdge);
  final canvas = web.HTMLCanvasElement()
    ..width = size.width
    ..height = size.height;
  final context = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
  context.drawImage(source, 0, 0, size.width, size.height);

  final encoded = Completer<web.Blob?>();
  canvas.toBlob(
    ((web.Blob? blob) => encoded.complete(blob)).toJS,
    'image/jpeg',
    DerivativeConfig.jpegQuality.toJS,
  );
  final jpeg = await encoded.future;
  if (jpeg == null) {
    throw Exception('the browser would not encode a JPEG');
  }
  final buffer = await jpeg.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}
