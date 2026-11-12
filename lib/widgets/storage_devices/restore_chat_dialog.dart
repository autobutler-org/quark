import 'package:flutter/widgets.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/storage_devices/restore_backup_dialog.dart';

/// Asks an admin to restore the chat from this snapshot-backup drive, and to
/// enter their own login password again (#2428): a [RestoreBackupDialog] that
/// says the restore replaces an empty chat only, and that accounts are
/// matched by username and must be created first.
///
/// Pops as [RestoreBackupDialog] does. Keys: `restore_chat_password`,
/// `restore_chat_cancel` and `restore_chat_confirm`.
class RestoreChatDialog extends StatelessWidget {
  /// Creates the dialog. [runs] are the drive's backups, newest first.
  const RestoreChatDialog({this.runs = const [], super.key});

  /// The backups the restore can read, newest first.
  final List<BackupRun> runs;

  @override
  Widget build(BuildContext context) {
    return RestoreBackupDialog(
      title: 'Restore chat from this drive',
      keyPrefix: 'restore_chat',
      runs: runs,
      paragraphs: const [
        'The restore replaces an empty chat. If chat already has messages or '
            'channels, it is refused and nothing changes.',
        'The backup does not carry accounts. Each person is matched by '
            'username, so create their accounts first.',
        'Each person unlocks chat with the password they had when the '
            'backup was taken.',
      ],
    );
  }
}
