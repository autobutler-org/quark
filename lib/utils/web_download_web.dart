import 'dart:convert';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Triggers a browser download of [data] as [fileName] through a temporary link. A file on the Quark
/// goes through [saveUrlForDownload] instead, so the browser streams it to disk.
Future<String?> saveBytesForDownload(Uint8List data, String fileName) async {
  final encoded = base64Encode(data);
  final anchor = web.HTMLAnchorElement()
    ..href = 'data:application/octet-stream;base64,$encoded'
    ..download = fileName
    ..style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();

  return fileName;
}

/// Hands [url] to the browser as a download, so the browser streams it to
/// disk rather than the app holding it in memory (#2226). [url] has to
/// authenticate on its own: a link sends no Authorization header.
Future<String?> saveUrlForDownload(Uri url, String fileName) async {
  final anchor = web.HTMLAnchorElement()
    ..href = url.toString()
    ..download = fileName
    ..style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();

  return fileName;
}
