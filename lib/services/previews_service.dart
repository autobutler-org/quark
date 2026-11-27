import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/document_viewer_config.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The URL one picture inside an office package is fetched from,
/// `GET /api/v0/previews/part`.
///
/// [part] is the zip entry (`word/media/image1.png`, `ppt/media/image3.png`).
/// [filePath] is the package on the device [serial] (null for the Quark's own
/// storage). The bearer token is added when the app holds one, so an image
/// widget, which cannot send an Authorization header, can still authenticate.
///
/// api: GET /api/v0/previews/part
Uri previewPartUrl(String part, {required String filePath, String? serial}) {
  final token = AppSettings.instance.bearerToken;
  return _previewUri('/api/v0/previews/part', filePath, serial, {
    'part': part,
    if (token != null && token.isNotEmpty) 'token': token,
  });
}

Uri _previewUri(
  String endpoint,
  String filePath,
  String? serial, [
  Map<String, String> extra = const {},
]) {
  final serialValue = serial?.trim() ?? '';
  final query = {
    'filePath': filePath,
    ...extra,
    if (serialValue.isNotEmpty) 'serial': serialValue,
  };
  return apiBaseUri
      .resolve(endpoint)
      .replace(
        query: query.entries
            .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
            .join('&'),
      );
}

/// Reads the converted forms the Quark serves for files it parses itself
/// (docs/architecture/read-only-documents.md): the app draws what comes
/// back and never opens the office file.
class PreviewsService {
  PreviewsService._();

  /// Reads the `.docx`, `.docm`, `.odt` or `.rtf` document at [path] as the
  /// block stream the document viewer draws.
  ///
  /// The stream is read whole, up to [DocumentViewerConfig.maxPreviewBytes],
  /// and parsed off the UI isolate. One the Quark cut off partway has no end
  /// line and throws a [FormatException], so half a document is never shown
  /// as a whole one. A refused request throws an [ApiException], a
  /// [DriveNotConnected] when the file's drive is unplugged.
  ///
  /// api: GET /api/v0/previews/document
  static Future<QuarkDocument> document(String path, {String? serial}) async {
    final request = http.Request(
      'GET',
      _previewUri('/api/v0/previews/document', path, serial),
    );
    final response = await FilesService.instance.authenticatedSend(request);
    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      // A refusal's body is the Quark's short JSON error, never the document.
      final body = await response.stream.bytesToString();
      throwFileApiError(status, body, 'Failed to preview the document');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      bytes.add(chunk);
      if (bytes.length > DocumentViewerConfig.maxPreviewBytes) {
        throw Exception('Document preview is larger than the viewer reads');
      }
    }
    return compute(_parseDocument, bytes.takeBytes());
  }
}

QuarkDocument _parseDocument(Uint8List bytes) =>
    QuarkDocument.parse(utf8.decode(bytes, allowMalformed: true));
