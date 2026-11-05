import 'dart:typed_data';

import 'package:quark/services/authenticated_service.dart';

/// The web build's stand-in for the native save dialog. The browser saves
/// downloads itself (`web_download_web.dart`), so nothing here is reached.
Future<String?> saveDownloadPlatform({
  required String Function(Map<String, String> headers) fileNameFor,
  required Future<DownloadedFile> Function() download,
}) => throw UnsupportedError('The web saves through the browser');

Future<String?> saveBytesPlatform(Uint8List bytes, String fileName) =>
    throw UnsupportedError('The web saves through the browser');

Future<String?> saveExistingFilePlatform({
  required String path,
  required String fileName,
}) => throw UnsupportedError('The web saves through the browser');
