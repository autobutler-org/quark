import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/restore_files_controller.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/widgets/storage_devices/restore_files_dialog.dart';

/// Restores the files on the snapshot-backup [device] once the admin
/// confirms in a [RestoreFilesDialog] (#4009), from the backup picked there
/// out of [runs], the drive's backups newest first (#4032). Cancel restores
/// nothing. The snack bar says where the files are going and from which
/// backup, or why the Quark refused; the copy itself runs as a job the jobs
/// panel follows.
///
/// [controller] is for tests; the default asks the Quark.
Future<void> restoreFilesFrom(
  BuildContext context,
  StorageDevice device, {
  List<BackupRun> runs = const [],
  RestoreFilesController? controller,
}) async {
  final choice = await QuarkWidget.showDialog<({bool toBuiltIn, String? run})>(
    context,
    builder: (ctx) => RestoreFilesDialog(runs: runs),
  );
  if (choice == null || !context.mounted) return;
  final restore = controller ?? RestoreFilesController();
  try {
    await restore.restore(
      deviceSerial: device.serial,
      missingToBuiltIn: choice.toBuiltIn,
      run: choice.run,
    );
    if (!context.mounted) return;
    final error = restore.error;
    showMessage(
      context,
      error != null
          ? Errors.backupRun(error, 'restore the files')
          : restore.summary ?? Errors.couldNot('restore the files'),
    );
  } finally {
    if (controller == null) restore.dispose();
  }
}
