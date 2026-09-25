/// Renders the thumbnail a photo or video carries with it when it is uploaded
/// (#2379), with the platform's own decoders, so the Quark never has to decode
/// H.264, HEVC or HEIC itself: a JPEG with a long edge of 400, rotation
/// applied.
///
/// Every function here returns null rather than throwing when it cannot
/// render: the file uploads either way, and one without a thumbnail gets
/// whatever the Quark can make of it, as from an older client.
///
/// The web renders with the browser (`createImageBitmap` for photos, a
/// `<video>` element for video). iOS and Android render nothing yet.
library;

import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/client_thumbnails_stub.dart'
    if (dart.library.js_interop) 'package:quark/services/client_thumbnails_web.dart'
    as platform;

/// The thumbnail of the file [name] whose bytes are already in memory.
Future<Uint8List?> renderThumbnailFromBytes(String name, Uint8List bytes) =>
    platform.renderThumbnailFromBytesPlatform(name, bytes);

/// The thumbnail of a file that arrived by drag and drop.
Future<Uint8List?> renderDroppedFileThumbnail(DropItemFile file) =>
    platform.renderDroppedFileThumbnailPlatform(file);

/// The multipart part that carries [thumbnail] after the file named
/// [fileName] in an upload. The Quark pairs it to its file by this filename,
/// so it must come after the file it belongs to.
http.MultipartFile thumbnailPart(String fileName, Uint8List thumbnail) =>
    http.MultipartFile.fromBytes('thumbnail', thumbnail, filename: fileName);
