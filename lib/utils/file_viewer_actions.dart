import 'package:flutter/material.dart';
import 'package:quark/pages/generic_file_viewer_open_stub.dart'
    if (dart.library.io) 'package:quark/pages/generic_file_viewer_open_native.dart'
    as native_open;
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';

/// Saves the file at [path] to this device and reports the outcome in a snack
/// bar: that it downloaded, or why it could not.
///
/// The viewers that offer Download share this, so the action reads the same
/// in each. [serial] is the device the file is on; null lets the Quark pick.
Future<void> downloadViewedFile(
  BuildContext context, {
  required String path,
  required String? serial,
  required String name,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  String message;
  try {
    await FilesService.saveFile(path, serial: serial, fileName: name);
    message = 'Downloaded $name';
  } catch (e) {
    message = Errors.message(e, 'download the file');
  }
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

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
