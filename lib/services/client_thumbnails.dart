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
/// `<video>` element for video). iOS and Android render with the platform
/// decoders through `fc_native_video_thumbnail` and `flutter_image_compress`,
/// which only the native build imports. Desktop renders video only (#3421),
/// on the player it plays video with: libmpv through media_kit on Linux, the
/// OS decoder through `fc_native_video_thumbnail` on macOS and Windows. A
/// codec that player cannot decode renders nothing, and desktop photos render
/// nothing. An STL, OBJ or PLY is drawn by the model viewer's own renderer
/// on every platform (#3227).
library;

import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/client_thumbnails_io.dart'
    if (dart.library.js_interop) 'package:quark/services/client_thumbnails_web.dart'
    as platform;
import 'package:quark/services/model_thumbnail_service.dart';
import 'package:quark/services/model_thumbnail_source.dart';
import 'package:quark/utils/model_thumbnail_config.dart';

/// The thumbnail of the file [name] whose bytes are already in memory.
Future<Uint8List?> renderThumbnailFromBytes(String name, Uint8List bytes) =>
    platform.renderThumbnailFromBytesPlatform(name, bytes);

/// The thumbnail of the file [name] on disk at [path]. The web has no paths
/// and renders nothing here. A 3D model is drawn by the model viewer's
/// renderer (#3227).
Future<Uint8List?> renderThumbnailFromPath(String name, String path) =>
    wantsModelThumbnail(name)
    ? renderModelThumbnailFromPath(name, path)
    : platform.renderThumbnailFromPathPlatform(name, path);

/// The thumbnail of the video [name] streamed from [url], which must carry
/// its own authentication (`FilesService.constructMediaUrl`). Only as much of
/// the video as the frame needs is read, through range requests. Anything
/// but a video renders nothing.
Future<Uint8List?> renderVideoThumbnailFromUrl(String name, Uri url) =>
    platform.renderVideoThumbnailFromUrlPlatform(name, url);

/// The thumbnail of a file that arrived by drag and drop.
Future<Uint8List?> renderDroppedFileThumbnail(DropItemFile file) =>
    wantsModelThumbnail(file.name)
    ? ModelThumbnailService.instance.renderForUpload(
        name: file.name,
        length: file.length,
        read: file.readAsBytes,
      )
    : platform.renderDroppedFileThumbnailPlatform(file);

/// The multipart part that carries [thumbnail] after the file named
/// [fileName] in an upload. The Quark pairs it to its file by this filename,
/// so it must come after the file it belongs to.
http.MultipartFile thumbnailPart(String fileName, Uint8List thumbnail) =>
    http.MultipartFile.fromBytes('thumbnail', thumbnail, filename: fileName);
