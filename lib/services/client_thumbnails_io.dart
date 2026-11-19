import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:quark/services/desktop_thumbnail_renderer.dart';
import 'package:quark/services/local_media_proxy.dart';
import 'package:quark/services/mobile_thumbnail_renderer.dart';

/// Only iOS and Android carry the photo and video plugins.
bool get _hasRenderer => Platform.isIOS || Platform.isAndroid;

/// Linux renders videos with libmpv, the player the app plays them with
/// (#3421). Photos and everything else on desktop render nothing, and the
/// Quark makes what thumbnail it can, as for an older client.
bool get _hasDesktopVideoRenderer => Platform.isLinux;

/// The thumbnail of an image already in memory. A video needs a path.
Future<Uint8List?> renderThumbnailFromBytesPlatform(
  String name,
  Uint8List bytes,
) async {
  if (!_hasRenderer) return null;
  return renderMobileThumbnail(name: name, bytes: bytes);
}

/// A full-size JPEG of an image in memory, on iOS and Android only.
Future<Uint8List?> convertImageToJpegPlatform(
  String name,
  Uint8List bytes,
) async {
  if (!_hasRenderer) return null;
  return renderMobileFullJpeg(name: name, bytes: bytes);
}

/// iOS and Android convert; desktop has no decoder for HEIC.
bool get canConvertImageToJpegPlatform => _hasRenderer;

/// The thumbnail of the file on disk at [path].
Future<Uint8List?> renderThumbnailFromPathPlatform(
  String name,
  String path,
) async {
  if (_hasDesktopVideoRenderer) {
    return renderDesktopVideoThumbnail(name: name, source: path);
  }
  if (!_hasRenderer) return null;
  return renderMobileThumbnail(name: name, path: path);
}

/// The thumbnail of a video streamed from [url]. A Quark on the home network
/// presents a self-signed certificate the native decoders do not trust, so
/// they read it through the same loopback proxy the video player uses.
Future<Uint8List?> renderVideoThumbnailFromUrlPlatform(
  String name,
  Uri url,
) async {
  if (!_hasRenderer && !_hasDesktopVideoRenderer) return null;
  Future<Uint8List?> render(Uri from) => _hasDesktopVideoRenderer
      ? renderDesktopVideoThumbnail(name: name, source: from.toString())
      : renderMobileVideoThumbnailFromUrl(name: name, url: from);
  if (!mediaNeedsLocalProxy(url)) return render(url);
  final proxy = await LocalMediaProxy.start(url);
  try {
    return await render(proxy.localUrl);
  } finally {
    await proxy.close();
  }
}

/// Drag and drop only reaches uploads on the web.
Future<Uint8List?> renderDroppedFileThumbnailPlatform(
  DropItemFile file,
) async => null;
