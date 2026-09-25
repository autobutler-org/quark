import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

/// Web: draws the player's `<video>` element onto a canvas at the video's own
/// resolution and encodes it as a PNG. video_player_web sets the element's
/// `src` to the controller's data source unchanged, which is how it is found;
/// [frameKey] is unused here, since a platform view is not part of Flutter's
/// layer tree and cannot be rasterized.
Future<Uint8List> captureVideoFramePlatform(
  VideoPlayerController controller,
  GlobalKey frameKey,
) async {
  final videos = web.document.querySelectorAll('video');
  web.HTMLVideoElement? video;
  for (var i = 0; i < videos.length && video == null; i++) {
    final element = videos.item(i);
    if (element.isA<web.HTMLVideoElement>() &&
        (element as web.HTMLVideoElement).getAttribute('src') ==
            controller.dataSource) {
      video = element;
    }
  }
  if (video == null) throw Exception('The video element is not on the page');
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
}
