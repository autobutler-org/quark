import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:quark/services/mobile_thumbnail_renderer.dart';

/// Only iOS and Android carry the plugins; desktop renders nothing and the
/// Quark makes what thumbnail it can, as for an older client.
bool get _hasRenderer => Platform.isIOS || Platform.isAndroid;

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
  if (!_hasRenderer) return null;
  return renderMobileThumbnail(name: name, path: path);
}

/// Drag and drop only reaches uploads on the web.
Future<Uint8List?> renderDroppedFileThumbnailPlatform(
  DropItemFile file,
) async => null;
