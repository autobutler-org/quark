import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';

/// One slice of a file: its [bytes], and the file's [totalSize] when the
/// Quark said what it is.
typedef CodeViewerRange = ({Uint8List bytes, int? totalSize});

/// Reads a file a byte range at a time for the code viewer (#2991), so a
/// 1 GB log costs one page of memory, not the file.
///
/// There is no endpoint of its own behind this: `GET /files/download` serves
/// through `http.ServeContent`, which honors a `Range` header.
class CodeViewerService {
  CodeViewerService._();

  /// Reads up to [length] bytes of [path] starting at byte [start].
  ///
  /// A [start] at or past the end of the file answers with no bytes. A Quark
  /// that ignores the range sends the whole file; reading stops at [length]
  /// either way. A refused request throws an [ApiException].
  ///
  /// api: GET /api/v0/files/download
  static Future<CodeViewerRange> readRange(
    String path, {
    required int start,
    required int length,
    String? serial,
  }) async {
    final request = http.Request(
      'GET',
      FilesService.downloadUrl(path, serial: serial),
    )..headers['Range'] = 'bytes=$start-${start + length - 1}';
    final response = await FilesService.instance.authenticatedSend(request);
    final status = response.statusCode;
    if (status == 416) {
      await response.stream.drain<void>();
      return (bytes: Uint8List(0), totalSize: _totalSize(response.headers));
    }
    if (status < 200 || status >= 300) {
      // An unread body pins the connection out of the pool.
      await response.stream.drain<void>();
      throw ApiException(status, 'Failed to read the file');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      bytes.add(chunk);
      if (bytes.length >= length) break;
    }
    final read = bytes.takeBytes();
    return (
      bytes: read.length > length
          ? Uint8List.sublistView(read, 0, length)
          : read,
      // A 200 is the whole file from byte 0, so its length is the size.
      totalSize: status == 206
          ? _totalSize(response.headers)
          : response.contentLength,
    );
  }

  /// The size after the slash of `Content-Range: bytes 0-99/1234`, or null
  /// when the header is missing or says `*`.
  static int? _totalSize(Map<String, String> headers) {
    final range = headers['content-range'];
    if (range == null) return null;
    return int.tryParse(range.substring(range.lastIndexOf('/') + 1).trim());
  }
}
