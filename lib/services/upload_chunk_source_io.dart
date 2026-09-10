import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/upload_chunk_source.dart';

/// A file on disk, read one range at a time.
///
/// [File.openRead] takes the range, so a chunk costs a seek and a read of that
/// many bytes — the rest of the file is never touched. Native uploads were
/// already streaming (`MultipartFile.fromPath`), and this keeps that true for
/// the chunked path (#1629).
class FileUploadChunkSource implements UploadChunkSource {
  FileUploadChunkSource._(this._file, this.size, this.lastModified);

  /// Opens [path], or returns null when it cannot be read.
  static Future<FileUploadChunkSource?> open(String path) async {
    try {
      final file = File(path);
      final stat = await file.stat();
      if (stat.type == FileSystemEntityType.notFound) {
        return null;
      }
      return FileUploadChunkSource._(file, stat.size, stat.modified);
    } catch (e) {
      debugPrint('[upload_chunk_source_io.dart] Cannot open $path: $e');
      return null;
    }
  }

  final File _file;

  @override
  final int size;

  @override
  final DateTime? lastModified;

  @override
  Future<http.Response> putRange({
    required Uri uri,
    required Map<String, String> headers,
    required int start,
    required int end,
  }) async {
    // Bounded by the chunk size, not the file size: openRead's range is the
    // whole point of this class.
    final bytes = await _readRange(start, end);
    return sharedHttpClient.put(uri, headers: headers, body: bytes);
  }

  Future<Uint8List> _readRange(int start, int end) async {
    final builder = BytesBuilder(copy: false);
    await for (final part in _file.openRead(start, end)) {
      builder.add(part);
    }
    return builder.takeBytes();
  }

  @override
  void release() {}
}

/// Drag and drop is web-only in this app today, but the code path is shared,
/// so the native side reads the dropped path off disk rather than refusing.
Future<UploadChunkSource?> openDroppedFileChunkSourcePlatform(
  DropItemFile file,
) {
  final path = file.path;
  if (path.isEmpty) {
    return Future<UploadChunkSource?>.value();
  }
  return FileUploadChunkSource.open(path);
}
