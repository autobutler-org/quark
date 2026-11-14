import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Asks an admin to delete one backup from a backup drive (#4044).
///
/// Says the delete can't be undone, and that it may free less space than the
/// backup's size: files that did not change are shared between backups. Pops
/// with true on Delete, or with nothing on Cancel.
class DeleteBackupRunDialog extends StatelessWidget {
  /// Creates the dialog for the backup named [runLabel], as "Nov 2, 09.00".
  const DeleteBackupRunDialog({required this.runLabel, super.key});

  /// What the app calls the backup.
  final String runLabel;

  @override
  Widget build(BuildContext context) {
    return ConfirmDeleteDialog(
      title: 'Delete this backup?',
      keyPrefix: 'delete_backup_run',
      onConfirm: () => Navigator.pop(context, true),
      onCancel: () => Navigator.pop(context),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "The backup of $runLabel is deleted for good. This can't be "
            'undone.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Backups share the files that did not change between them, so '
            'deleting one may free less space than its size.',
          ),
        ],
      ),
    );
  }
}
