import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

/// Web: loads the video into a second, detached `<video>` fetched in CORS
/// mode, seeks it to where the player is, draws that frame onto a canvas at
/// the video's own resolution and encodes it as a PNG.
///
/// The player's own element cannot be drawn: video_player_web fetches it
/// without `crossOrigin`, so whenever the media URL (built from the active
/// host) is on another origin than the page, the canvas is tainted and
/// `toBlob` throws a SecurityError. The Quark answers CORS requests with
/// `Access-Control-Allow-Origin: *` and the media URL carries its own token,
/// so an anonymous CORS fetch is both allowed and authenticated. [frameKey] is
/// unused here, since a platform view is not part of Flutter's layer tree.
Future<Uint8List> captureVideoFramePlatform(
  VideoPlayerController controller,
  GlobalKey frameKey,
) async {
  final position = await controller.position ?? controller.value.position;
  final video = web.HTMLVideoElement()
    ..crossOrigin = 'anonymous'
    ..muted = true
    ..preload = 'auto';
  try {
    final metadata = _until(video.onLoadedMetadata.first, video);
    video.src = controller.dataSource;
    await metadata;
    final seeked = _until(video.onSeeked.first, video);
    video.currentTime =
        position.inMicroseconds / Duration.microsecondsPerSecond;
    await seeked;
    final canvas = web.HTMLCanvasElement()
      ..width = video.videoWidth
      ..height = video.videoHeight;
    (canvas.getContext('2d')! as web.CanvasRenderingContext2D).drawImage(
      video,
      0,
      0,
    );
    final blob = Completer<web.Blob?>();
    canvas.toBlob(((web.Blob? b) => blob.complete(b)).toJS, 'image/png');
    final png = await blob.future;
    if (png == null) throw Exception('The frame could not be encoded');
    final buffer = await png.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  } finally {
    video
      ..removeAttribute('src')
      ..load();
  }
}

/// [event], or a failure if [video] errors first or nothing happens in time.
Future<void> _until(Future<web.Event> event, web.HTMLVideoElement video) =>
    Future.any([
      event,
      video.onError.first.then(
        (_) => throw Exception(
          'The video failed to load: ${video.error?.message}',
        ),
      ),
    ]).timeout(const Duration(seconds: 30));
