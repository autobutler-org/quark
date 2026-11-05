import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/web_download_stub.dart'
    if (dart.library.html) 'package:quark/utils/web_download_web.dart'
    as web_download;

/// The browser has no file to hand to a save dialog. The decrypted bytes are
/// downloaded the way other browser saves are, with no size cap.
Future<String?> saveChatAttachmentToDevicePlatform({
  required Stream<List<int>> plaintext,
  required String fileName,
}) async {
  final bytes = await _collect(plaintext);
  return web_download.saveBytesForDownload(bytes, fileName);
}

/// The browser has no path to upload from. The bytes go through the same
/// form upload as a file picked on the web, and a taken name is kept.
Future<void> uploadChatAttachmentToFolderPlatform({
  required Stream<List<int>> plaintext,
  required String folder,
  required String fileName,
}) async {
  final bytes = await _collect(plaintext);
  await FilesService.uploadFilesFromFormData(toRootDir(folder), [
    http.MultipartFile.fromBytes('files', bytes, filename: fileName),
  ], keepBoth: true);
}

Future<Uint8List> _collect(Stream<List<int>> plaintext) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in plaintext) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}
