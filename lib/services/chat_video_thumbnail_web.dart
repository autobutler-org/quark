import 'dart:typed_data';

import 'package:quark/services/client_thumbnails.dart';

/// The browser's `<video>` element, seeked the same way an upload thumbnail is.
Future<Uint8List?> chatVideoThumbnailPlatform(String name, Uint8List bytes) =>
    renderThumbnailFromBytes(name, bytes);
