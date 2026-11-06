import 'dart:typed_data';

import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/file_save_io.dart'
    if (dart.library.js_interop) 'package:quark/services/file_save_web.dart'
    as platform;

/// Saves a download through the platform's native save dialog and returns
/// where it landed, or null when the user canceled.
///
/// Android and iOS add a picture or video to the photo library — Apple Photos,
/// the gallery — and hand anything else to `flutter_file_dialog`, which copies
/// it out of the temp file [download] streams to (#3334). Declining photo
/// access sends the file to the dialog instead, and `downloadNotices` says
/// why. Desktop asks for the destination
/// first through `file_picker`, then streams the download and moves it there,
/// so a canceled save downloads nothing and writes nothing (#3150). Either way
/// the body never enters memory (#1723).
///
/// [fileNameFor] names the file from the download's response headers; desktop
/// asks before any response exists, so it is called with no headers there.
/// The web saves through the browser instead and never reaches this.
Future<String?> saveDownloadThroughDialog({
  required String Function(Map<String, String> headers) fileNameFor,
  required Future<DownloadedFile> Function() download,
}) =>
    platform.saveDownloadPlatform(fileNameFor: fileNameFor, download: download);

/// Saves [bytes] as [fileName] through the platform's native save dialog and
/// returns where they landed, or null when the user canceled. On a phone a
/// picture or video goes to the photo library, as [saveDownloadThroughDialog]
/// does.
Future<String?> saveBytesThroughDialog(Uint8List bytes, String fileName) =>
    platform.saveBytesPlatform(bytes, fileName);

/// Saves the file already at [path], named [fileName], through the same photo
/// library or save dialog as [saveBytesThroughDialog].
///
/// Nothing is read into one buffer. [path] is left in place for the caller
/// to delete. Returns where it landed, or null when the user canceled. The
/// web does not reach this.
Future<String?> saveExistingFileThroughDialog({
  required String path,
  required String fileName,
}) => platform.saveExistingFilePlatform(path: path, fileName: fileName);
