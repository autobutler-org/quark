import 'package:material_ui/material_ui.dart';
import 'package:quark/pages/generic_file_viewer_open_stub.dart'
    if (dart.library.io) 'package:quark/pages/generic_file_viewer_open_native.dart'
    as native_open;
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';

/// Saves the file at [path] to this device and reports the outcome in a snack
/// bar: that it downloaded, or why it could not. Canceling the save dialog says
/// nothing (#3160).
///
/// The viewers that offer Download share this, so the action reads the same
/// in each. [serial] is the device the file is on; null lets the Quark pick.
/// The save goes through [saveViewedFile].
Future<void> downloadViewedFile(
  BuildContext context, {
  required String path,
  required String? serial,
  required String name,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  String message;
  try {
    final saved = await saveViewedFile(path, serial: serial, fileName: name);
    if (saved == null) return;
    message = 'Downloaded $name';
  } catch (e) {
    message = Errors.message(e, 'download the file');
  }
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

/// What [downloadViewedFile] saves with: returns where the file landed, or
/// null when the user canceled. A test, which has no save dialog, swaps it.
@visibleForTesting
Future<String?> Function(String path, {String? serial, String? fileName})
saveViewedFile = FilesService.saveFile;

/// Hands the file at [path] to whichever app the system picks for it, and
/// reports in a snack bar when that fails. Not available on web.
Future<void> openViewedFileWithSystem(
  BuildContext context, {
  required String path,
  required String? serial,
  required String name,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  String message;
  try {
    final local = await FilesService.downloadForOpenWith(
      path,
      serial: serial,
      fileName: name,
    );
    message = await native_open.openFileWithSystem(local);
  } catch (e) {
    message = Errors.message(e, 'open the file');
  }
  if (message.isNotEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
