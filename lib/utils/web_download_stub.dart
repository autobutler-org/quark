import 'dart:typed_data';

/// The non-web build's stand-in for a browser download of bytes. It saves nothing and returns null, as does
/// [saveUrlForDownload].
Future<String?> saveBytesForDownload(Uint8List data, String fileName) async {
  return null;
}

Future<String?> saveUrlForDownload(Uri url, String fileName) async {
  return null;
}
