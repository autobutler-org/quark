import 'dart:typed_data';

/// A build with no video decoder for a chat preview.
Future<Uint8List?> chatVideoThumbnailPlatform(String name, Uint8List bytes) =>
    Future<Uint8List?>.value();
