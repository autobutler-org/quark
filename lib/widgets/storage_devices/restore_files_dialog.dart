import 'package:material_ui/material_ui.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/backup_run_label.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Asks an admin to restore the files on this snapshot-backup drive to the
/// drives they were copied from (#4009).
///
/// Names the backup it restores, the newest of [runs] unless another is
/// picked (#4032). Says that files deleted since the snapshot come back and
/// that a file already on the Quark is kept as it is. Pops with whether the
/// files of a drive that is no longer attached go to built-in storage and
/// the picked run, null when [runs] is empty, or with nothing on Cancel.
class RestoreFilesDialog extends StatefulWidget {
  /// Creates the dialog. [runs] are the drive's backups, newest first.
  const RestoreFilesDialog({this.runs = const [], super.key});

  /// The backups the restore can read, newest first.
  final List<BackupRun> runs;

  @override
  State<RestoreFilesDialog> createState() => _RestoreFilesDialogState();
}

class _RestoreFilesDialogState extends State<RestoreFilesDialog> {
  bool _toBuiltIn = false;
  late String? _run = widget.runs.firstOrNull?.folder;

  @override
  Widget build(BuildContext context) {
    return QuarkWidget.alertDialog(
      title: const Text('Restore files from this drive'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_run case final run?) ...[
            BackupRunPicker(
              runs: [for (final r in widget.runs) backupRunItem(r)],
              selected: run,
              onSelected: (picked) => setState(() => _run = picked),
            ),
            const SizedBox(height: 12),
          ],
          const Text(
            'Each drive\'s files go back onto that drive. A file already '
            'there is kept as it is.',
          ),
          const SizedBox(height: 12),
          const Text(
            'A snapshot keeps files that were deleted since, so the restore '
            'brings them back too.',
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            key: const ValueKey('restore_files_to_built_in'),
            contentPadding: EdgeInsets.zero,
            value: _toBuiltIn,
            onChanged: (value) => setState(() => _toBuiltIn = value ?? false),
            title: const Text(
              'Put the files of a drive that is not attached on built-in '
              'storage',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('restore_files_cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('restore_files_confirm'),
          onPressed: () =>
              Navigator.pop(context, (toBuiltIn: _toBuiltIn, run: _run)),
          child: const Text('Restore'),
        ),
      ],
    );
  }
}
