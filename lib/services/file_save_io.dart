import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/download_destination.dart';
import 'package:quark/services/download_notices.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_kind.dart';

/// Asks the user where to save a file named [fileName], and returns the path
/// they chose, or null when they canceled.
typedef SavePathPicker = Future<String?> Function(String fileName);

/// `flutter_file_dialog` implements only Android and iOS; every other native
/// platform saves through `file_picker` instead (#3150).
bool get _usesMobileDialog => Platform.isAndroid || Platform.isIOS;

/// The native save of a download: on Android and iOS the photo library for a
/// picture or video and the mobile dialog for anything else, the desktop
/// dialog everywhere else. See `saveDownloadThroughDialog`.
Future<String?> saveDownloadPlatform({
  required String Function(Map<String, String> headers) fileNameFor,
  required Future<DownloadedFile> Function() download,
}) async {
  if (!_usesMobileDialog) {
    return saveDownloadToPickedPath(
      fileName: fileNameFor(const {}),
      download: download,
      pickPath: _pickDesktopSavePath,
    );
  }
  final downloaded = await download();
  try {
    final fileName = fileNameFor(downloaded.headers);
    // The photo library reads the format from the extension, and the temp
    // file has none. It sits alone in its own directory, which delete removes.
    final source = await File(
      downloaded.path,
    ).rename('${downloaded.path}${fileExtension(fileName)}');
    // Awaited, not just returned: the finally below deletes the temp file, and
    // an unawaited future would let that race the save reading it.
    return await saveToPhotoLibraryOrFiles(
      destination: downloadDestinationFor(fileName),
      requestAccess: _requestPhotoLibraryAccess,
      saveToLibrary: (destination) =>
          _saveFileToPhotoLibrary(source, fileName, destination),
      saveToFiles: () => FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          sourceFilePath: source.path,
          fileName: fileName,
        ),
      ),
      notify: announceDownloadNotice,
    );
  } finally {
    await downloaded.delete();
  }
}

/// The native save of [bytes]: on Android and iOS the photo library for a
/// picture or video and the mobile dialog for anything else, the desktop
/// dialog everywhere else.
Future<String?> saveBytesPlatform(Uint8List bytes, String fileName) {
  if (!_usesMobileDialog) {
    return saveBytesToPickedPath(
      bytes,
      fileName: fileName,
      pickPath: _pickDesktopSavePath,
    );
  }
  return saveToPhotoLibraryOrFiles(
    destination: downloadDestinationFor(fileName),
    requestAccess: _requestPhotoLibraryAccess,
    saveToLibrary: (destination) async {
      if (destination == DownloadDestination.photoLibraryImage) {
        final entity = await PhotoManager.editor.saveImage(
          bytes,
          filename: fileName,
          title: fileName,
        );
        return entity.id;
      }
      // A video can only be added from a file, so the bytes go to one first.
      final dir = await Directory.systemTemp.createTemp('quark_save_');
      try {
        final file = File('${dir.path}/video${fileExtension(fileName)}');
        await file.writeAsBytes(bytes, flush: true);
        return await _saveFileToPhotoLibrary(file, fileName, destination);
      } finally {
        await dir.delete(recursive: true);
      }
    },
    saveToFiles: () => FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(data: bytes, fileName: fileName),
    ),
    notify: announceDownloadNotice,
  );
}

/// Saves the file already at [path] the way [saveBytesPlatform] saves bytes:
/// the photo library for a picture or video, the mobile dialog otherwise, and
/// the desktop dialog on desktop. [path] is not read into memory and is not
/// deleted.
Future<String?> saveExistingFilePlatform({
  required String path,
  required String fileName,
}) async {
  if (!_usesMobileDialog) {
    final destination = await _pickDesktopSavePath(fileName);
    if (destination == null) return null;
    try {
      await File(path).copy(destination);
    } catch (_) {
      _removePlaceholder(destination);
      rethrow;
    }
    return destination;
  }
  return saveToPhotoLibraryOrFiles(
    destination: downloadDestinationFor(fileName),
    requestAccess: _requestPhotoLibraryAccess,
    saveToLibrary: (destination) =>
        _saveFileToPhotoLibrary(File(path), fileName, destination),
    saveToFiles: () => FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(sourceFilePath: path, fileName: fileName),
    ),
    notify: announceDownloadNotice,
  );
}

/// The mobile save (#3334): a picture or video goes into the photo library
/// when [requestAccess] allows it, anything else through [saveToFiles].
///
/// A person who declines photo access still gets the file, through
/// [saveToFiles], and [notify] tells them why it went there. A file the
/// library refuses (a format it cannot read) goes to [saveToFiles] as well,
/// so a download is never lost to the library's choosiness. Returns where the
/// file landed — the library's asset id, or the saved path — or null when the
/// save dialog was canceled.
@visibleForTesting
Future<String?> saveToPhotoLibraryOrFiles({
  required DownloadDestination destination,
  required Future<bool> Function() requestAccess,
  required Future<String> Function(DownloadDestination destination)
  saveToLibrary,
  required Future<String?> Function() saveToFiles,
  required void Function(String notice) notify,
}) async {
  if (destination == DownloadDestination.files) return saveToFiles();
  if (!await requestAccess()) {
    final saved = await saveToFiles();
    if (saved != null) notify(Errors.photoLibraryAccessDenied);
    return saved;
  }
  try {
    return await saveToLibrary(destination);
  } catch (_) {
    // The library refused this file; the save dialog takes anything.
    return saveToFiles();
  }
}

/// Asks for permission to add to the photo library: add-only on iOS, which
/// is all a save needs, and pictures on Android, whose manifest declares
/// `READ_MEDIA_IMAGES` already for the Photos page.
Future<bool> _requestPhotoLibraryAccess() async {
  final state = await PhotoManager.requestPermissionExtend(
    requestOption: const PermissionRequestOption(
      iosAccessLevel: IosAccessLevel.addOnly,
      androidPermission: AndroidPermission(
        type: RequestType.image,
        mediaLocation: false,
      ),
    ),
  );
  return state.hasAccess;
}

/// Adds [file] to the photo library as [destination] says, named [fileName],
/// and returns the new asset's id.
Future<String> _saveFileToPhotoLibrary(
  File file,
  String fileName,
  DownloadDestination destination,
) async {
  final entity = destination == DownloadDestination.photoLibraryVideo
      ? await PhotoManager.editor.saveVideo(file, title: fileName)
      : await PhotoManager.editor.saveImageWithPath(file.path, title: fileName);
  return entity.id;
}

/// The desktop save: asks [pickPath] for a destination first, and only then
/// streams [download] and moves it there. Canceling the dialog downloads and
/// writes nothing. Returns the destination, or null when canceled.
@visibleForTesting
Future<String?> saveDownloadToPickedPath({
  required String fileName,
  required Future<DownloadedFile> Function() download,
  required SavePathPicker pickPath,
}) async {
  final destination = await pickPath(fileName);
  if (destination == null) return null;
  try {
    final downloaded = await download();
    try {
      final source = File(downloaded.path);
      try {
        await source.rename(destination);
      } on FileSystemException {
        // A rename cannot cross filesystems, and the temp directory is often
        // on its own. A copy streams, so it costs no more memory than a move.
        await source.copy(destination);
      }
    } finally {
      await downloaded.delete();
    }
  } catch (_) {
    _removePlaceholder(destination);
    rethrow;
  }
  return destination;
}

/// The desktop save of [bytes]: asks [pickPath] for a destination and writes
/// them there. Returns the destination, or null when canceled.
@visibleForTesting
Future<String?> saveBytesToPickedPath(
  Uint8List bytes, {
  required String fileName,
  required SavePathPicker pickPath,
}) async {
  final destination = await pickPath(fileName);
  if (destination == null) return null;
  await File(destination).writeAsBytes(bytes, flush: true);
  return destination;
}

/// The Linux picker writes the bytes it is handed to the chosen path before
/// returning. It is handed none, so a failed download would otherwise leave an
/// empty file behind where the user expected theirs.
///
/// One stat and one unlink, done synchronously: a failed save should report
/// at once, not after a round of the event loop.
void _removePlaceholder(String path) {
  try {
    final file = File(path);
    if (file.lengthSync() == 0) file.deleteSync();
  } catch (_) {
    // Nothing there, or nothing we may touch: either way, nothing to clean.
  }
}

/// Opens `file_picker`'s save dialog. On Linux that is the XDG desktop portal's
/// FileChooser over D-Bus, so the session needs `xdg-desktop-portal` and a
/// backend for it (GTK, KDE, GNOME, ...); there is no command-line dialog
/// fallback.
///
/// `file_picker` demands bytes to write, but the download has not happened
/// yet: it gets none, and the caller streams the file over what it wrote.
Future<String?> _pickDesktopSavePath(String fileName) async {
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Save file',
    fileName: fileName,
    bytes: Uint8List(0),
  );
  return uri?.toFilePath();
}
