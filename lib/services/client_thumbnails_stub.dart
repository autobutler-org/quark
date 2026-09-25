import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';

/// No renderer on this platform yet, so nothing is rendered and the Quark
/// makes what thumbnail it can, as it does for an older client.
Future<Uint8List?> renderThumbnailFromBytesPlatform(
  String name,
  Uint8List bytes,
) async => null;

/// See [renderThumbnailFromBytesPlatform].
Future<Uint8List?> renderDroppedFileThumbnailPlatform(
  DropItemFile file,
) async => null;
