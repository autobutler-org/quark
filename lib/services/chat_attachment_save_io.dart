import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:quark/models/upload_conflict.dart';
import 'package:quark/models/upload_session.dart';
import 'package:quark/services/file_save.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/resumable_upload_service.dart';
import 'package:quark/services/upload_chunk_source.dart';
import 'package:quark/services/upload_chunk_source_io.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/upload_config.dart';

/// Writes [plaintext] to a temporary file and saves it through the photo
/// library or the save dialog. The temporary file is removed afterward.
Future<String?> saveChatAttachmentToDevicePlatform({
  required Stream<List<int>> plaintext,
  required String fileName,
}) => _withPlaintextFile(plaintext, fileName, (file) {
  return saveExistingFileThroughDialog(path: file.path, fileName: fileName);
});

/// Writes [plaintext] to a temporary file and uploads it into [folder].
///
/// Below [UploadConfig.chunkedUploadThresholdBytes] that is the multipart
/// form upload, from the file rather than from a buffer. At or above it, it
/// is a resumable session, the same split the file browser uses for a local
/// file. Either way a taken name is kept and this file lands beside it. The
/// temporary file is removed when the upload finishes or fails.
Future<void> uploadChatAttachmentToFolderPlatform({
  required Stream<List<int>> plaintext,
  required String folder,
  required String fileName,
}) => _withPlaintextFile(plaintext, fileName, (file) async {
  final rootDir = toRootDir(folder);
  final length = await file.length();
  if (length >= UploadConfig.chunkedUploadThresholdBytes) {
    final source = await FileUploadChunkSource.open(file.path);
    if (source != null) {
      try {
        await _uploadChunked(
          source: source,
          rootDir: rootDir,
          fileName: fileName,
        );
        return;
      } finally {
        source.release();
      }
    }
  }
  final part = await http.MultipartFile.fromPath(
    'files',
    file.path,
    filename: fileName,
  );
  await FilesService.uploadFilesFromFormData(rootDir, [part], keepBoth: true);
});

/// A name safe to put in a temporary directory. [fileName] is what the save
/// dialog and the upload call the file; this is only the on-disk name.
String _tempFileName(String fileName) {
  final base = fileName.split(RegExp(r'[/\\]')).last.trim();
  final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (safe.isEmpty || safe == '.' || safe == '..') return 'file';
  return safe;
}

Future<T> _withPlaintextFile<T>(
  Stream<List<int>> plaintext,
  String fileName,
  Future<T> Function(File file) use,
) async {
  final dir = await Directory.systemTemp.createTemp('quark-chat-save-');
  try {
    final file = File('${dir.path}/${_tempFileName(fileName)}');
    final handle = await file.open(mode: FileMode.write);
    try {
      await for (final chunk in plaintext) {
        await handle.writeFrom(chunk);
      }
    } finally {
      await handle.close();
    }
    return await use(file);
  } finally {
    try {
      await dir.delete(recursive: true);
    } on Object {
      // The photo library or the save dialog may still be holding the file.
      // Leaving the temporary directory is better than failing a save that
      // already finished.
    }
  }
}

Future<void> _uploadChunked({
  required UploadChunkSource source,
  required String rootDir,
  required String fileName,
}) async {
  final client = ResumableUploadService.instance;
  final total = source.size;
  final session = await client.createSession(
    rootDir: rootDir,
    fileName: fileName,
    totalSize: total,
    conflict: UploadConflictChoice.keepBoth,
  );
  var offset = session.offset;
  var stalled = 0;
  try {
    while (offset < total) {
      final end = math.min(offset + UploadConfig.chunkSizeBytes, total);
      final outcome = await client.putChunk(
        sessionId: session.sessionId,
        source: source,
        start: offset,
        end: end,
        totalSize: total,
      );
      switch (outcome) {
        case ChunkAccepted(offset: final committed, complete: final complete):
          if (complete) return;
          stalled = _countStall(stalled, committed, offset, fileName);
          offset = committed;
        case ChunkOffsetMismatch(offset: final committed):
          stalled = _countStall(stalled, committed, offset, fileName);
          offset = committed;
        case ChunkSessionGone():
          throw Exception('the upload session ended before $fileName landed');
        case ChunkRejected(:final message):
          throw Exception(message);
      }
    }
    throw Exception('server holds all of $fileName but did not commit it');
  } catch (_) {
    await client.deleteSession(session.sessionId);
    rethrow;
  }
}

int _countStall(int stalled, int committed, int offset, String fileName) {
  if (committed > offset) return 0;
  final next = stalled + 1;
  if (next > UploadConfig.maxChunkAttempts) {
    throw Exception('server kept reporting offset $committed for $fileName');
  }
  return next;
}
