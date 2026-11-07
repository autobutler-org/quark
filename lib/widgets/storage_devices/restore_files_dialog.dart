import 'package:flutter/material.dart';
import 'package:quark/utils/quark_widget.dart';

/// Asks an admin to restore the files on this snapshot-backup drive to the
/// drives they were copied from (#4009).
///
/// Says that files deleted since the snapshot come back and that a file
/// already on the Quark is kept as it is. Pops with whether the files of a
/// drive that is no longer attached go to built-in storage, or with nothing
/// on Cancel.
class RestoreFilesDialog extends StatefulWidget {
  /// Creates the dialog.
  const RestoreFilesDialog({super.key});

  @override
  State<RestoreFilesDialog> createState() => _RestoreFilesDialogState();
}

class _RestoreFilesDialogState extends State<RestoreFilesDialog> {
  bool _toBuiltIn = false;

  @override
  Widget build(BuildContext context) {
    return QuarkWidget.alertDialog(
      title: const Text('Restore files from this drive'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          onPressed: () => Navigator.pop(context, _toBuiltIn),
          child: const Text('Restore'),
        ),
      ],
    );
  }
}
