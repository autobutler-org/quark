import 'package:flutter/widgets.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/storage_devices/restore_backup_dialog.dart';

/// Asks an admin to restore every vault from this snapshot-backup drive, and
/// to enter their own login password again: a [RestoreBackupDialog] that says
/// how vaults find their accounts.
///
/// Pops as [RestoreBackupDialog] does. Keys: `restore_vault_password`,
/// `restore_vault_cancel` and `restore_vault_confirm`.
class RestoreVaultDialog extends StatelessWidget {
  /// Creates the dialog. [runs] are the drive's backups, newest first.
  const RestoreVaultDialog({this.runs = const [], super.key});

  /// The backups the restore can read, newest first.
  final List<BackupRun> runs;

  @override
  Widget build(BuildContext context) {
    return RestoreBackupDialog(
      title: 'Restore vaults from this drive',
      keyPrefix: 'restore_vault',
      runs: runs,
      paragraphs: const [
        'Each vault goes to the account with exactly the same username. '
            'Carol is not carol.',
        'Every vault in the backup must have its account here first, or '
            'nothing is restored.',
        'After a move to new hardware, each person unlocks their vault '
            'with the password they had when the backup was taken.',
      ],
    );
  }
}
