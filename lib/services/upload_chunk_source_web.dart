import 'dart:js_interop';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/upload_chunk_source.dart';
import 'package:web/web.dart' as web;

/// A `Blob` the browser is holding, sent one slice at a time.
///
/// `Blob.slice` is a view, not a copy — the browser keeps the backing bytes
/// wherever it already had them (usually on disk) and only reads the range
/// when something consumes the slice. Handing that slice straight to `fetch`
/// is what keeps a multi-gigabyte file out of the tab's heap; going through
/// `package:http` instead would materialize it, which is the trap #1629
/// describes.
class BlobUploadChunkSource implements UploadChunkSource {
  BlobUploadChunkSource(this._blob, {this.lastModified});

  final web.Blob _blob;

  @override
  int get size => _blob.size;

  @override
  final DateTime? lastModified;

  /// api: none
  @override
  Future<http.Response> putRange({
    required Uri uri,
    required Map<String, String> headers,
    required int start,
    required int end,
  }) async {
    final requestHeaders = web.Headers();
    for (final header in headers.entries) {
      requestHeaders.append(header.key, header.value);
    }

    final response = await web.window
        .fetch(
          uri.toString().toJS,
          web.RequestInit(
            method: 'PUT',
            headers: requestHeaders,
            body: _blob.slice(start, end),
          ),
        )
        .toDart;

    final body = (await response.text().toDart).toDart;
    // Only the headers the session protocol reads. Copying the whole set would
    // mean walking a JS iterator for nothing.
    final offset = response.headers.get('X-Upload-Offset');
    return http.Response(
      body,
      response.status,
      headers: {'x-upload-offset': ?offset},
    );
  }

  @override
  void release() {}
}

/// api: none
Future<UploadChunkSource?> openDroppedFileChunkSourcePlatform(
  DropItemFile file,
) async {
  final path = file.path;
  if (path.isEmpty) {
    return null;
  }

  try {
    // The dropped item is an object URL standing in for a Blob the browser
    // already holds. Fetching it hands back that Blob rather than a copy of
    // its bytes, so this costs a handle and not a read.
    final response = await web.window.fetch(path.toJS).toDart;
    final blob = await response.blob().toDart;
    return BlobUploadChunkSource(blob, lastModified: await file.lastModified());
  } catch (e) {
    debugPrint('[upload_chunk_source_web.dart] Cannot open ${file.name}: $e');
    return null;
  }
}
