import 'dart:typed_data';

import 'package:quark/services/chat_video_thumbnail_stub.dart'
    if (dart.library.io) 'package:quark/services/chat_video_thumbnail_io.dart'
    if (dart.library.js_interop) 'package:quark/services/chat_video_thumbnail_web.dart';

/// A JPEG preview of the video [name], or null when this device cannot
/// decode one. [bytes] are the plaintext file.
Future<Uint8List?> chatVideoThumbnail(String name, Uint8List bytes) =>
    chatVideoThumbnailPlatform(name, bytes);
