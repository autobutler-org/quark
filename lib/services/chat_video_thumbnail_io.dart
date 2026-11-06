import 'dart:io';
import 'dart:typed_data';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail_platform_interface.dart';
import 'package:quark/utils/client_thumbnail_config.dart';
import 'package:quark/utils/file_kind.dart';

/// Writes [bytes] to a temp file and asks the platform decoder for one JPEG.
///
/// Upload thumbnails stay on the phone. This is only for a chat preview, and
/// the same plugin also runs on macOS.
Future<Uint8List?> chatVideoThumbnailPlatform(
  String name,
  Uint8List bytes,
) async {
  if (fileKindForName(name) != FileKind.video) return null;
  final dir = await Directory.systemTemp.createTemp('quark-chat-thumb-');
  try {
    final file = File('${dir.path}/video.mp4');
    await file.writeAsBytes(bytes, flush: true);
    return await FcNativeVideoThumbnail().saveThumbnailToBytes(
      srcFile: file.path,
      srcFileUri: false,
      width: ClientThumbnailConfig.longEdge,
      height: ClientThumbnailConfig.longEdge,
      format: 'jpeg',
      at: FcVideoThumbnailTime(
        ClientThumbnailConfig.videoFrameAt.inMilliseconds,
        FcVideoThumbnailTimeUnit.milliseconds,
      ),
    );
  } on Object {
    return null;
  } finally {
    try {
      await dir.delete(recursive: true);
    } on Object {
      // The decoder may still have the file open.
    }
  }
}
