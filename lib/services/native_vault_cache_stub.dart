/// Web stand-in for the native vault cache. A browser has no autofill
/// extension to share with, so there is no directory and nothing is stored,
/// and this file does not call `dart:io`.
library;

/// Always none on web.
Future<String?> defaultDirectory() async => null;

/// Does nothing on web.
Future<void> replaceOnly(String dir, String name, String contents) async {}

/// Does nothing on web.
Future<void> deleteDirectory(String dir) async {}
