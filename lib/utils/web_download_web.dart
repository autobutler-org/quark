// cspell:ignore HTMLI
import 'dart:async';
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

/// Submits [fields] as a form POST to [action] and lets the browser save the
/// response, streaming it to disk, for a download whose input is too large
/// for a link (#4195). [action] has to authenticate on its own: a form sends
/// no Authorization header. The form targets a hidden frame, so an error
/// answer lands there rather than replacing the app. Returns null, since the
/// browser names the file from the response.
Future<String?> submitFormForDownload(
  Uri action,
  Map<String, String> fields,
) async {
  final frameName = 'quark_download_${DateTime.now().microsecondsSinceEpoch}';
  final frame = web.HTMLIFrameElement()
    ..name = frameName
    ..style.display = 'none';
  final form = web.HTMLFormElement()
    ..method = 'POST'
    ..action = action.toString()
    ..target = frameName
    ..style.display = 'none';
  for (final MapEntry(:key, :value) in fields.entries) {
    form.append(
      web.HTMLInputElement()
        ..type = 'hidden'
        ..name = key
        ..value = value,
    );
  }
  web.document.body?.append(frame);
  web.document.body?.append(form);
  form.submit();
  form.remove();
  // The browser hands the response to its downloads once it starts; the
  // frame only has to outlive that.
  Timer(const Duration(minutes: 1), () => frame.remove());
  return null;
}
