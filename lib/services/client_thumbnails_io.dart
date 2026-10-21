import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:quark/services/client_thumbnails_desktop.dart';
import 'package:quark/services/client_thumbnails_desktop_players.dart';
import 'package:quark/services/local_media_proxy.dart';
import 'package:quark/services/mobile_thumbnail_renderer.dart';

/// iOS and Android carry the photo and video plugins.
bool get _hasRenderer => Platform.isIOS || Platform.isAndroid;

/// Desktop renders video on its own player (#3421) and photos not at all; the
/// Quark makes what thumbnail it can of those, as for an older client.
bool get _isDesktop =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

/// The thumbnail of an image already in memory. A video needs a path.
Future<Uint8List?> renderThumbnailFromBytesPlatform(
  String name,
  Uint8List bytes,
) async {
  if (!_hasRenderer) return null;
  return renderMobileThumbnail(name: name, bytes: bytes);
}

/// The thumbnail of the file on disk at [path].
Future<Uint8List?> renderThumbnailFromPathPlatform(
  String name,
  String path,
) async {
  if (_isDesktop) {
    return renderDesktopVideoThumbnail(
      name: name,
      source: path,
      open: openDesktopVideo,
    );
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
  if (!_hasRenderer && !_isDesktop) return null;
  Future<Uint8List?> render(Uri from) => _isDesktop
      ? renderDesktopVideoThumbnail(
          name: name,
          source: from.toString(),
          open: openDesktopVideo,
        )
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
