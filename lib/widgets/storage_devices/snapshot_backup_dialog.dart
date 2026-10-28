import 'package:flutter/material.dart';
import 'package:quark/utils/quark_widget.dart';

/// Confirms a snapshot backup to the drive named [targetName]. Pops with
/// `true` on Start Backup, or with nothing on Cancel.
///
/// It asks for no password (#3460): the chat and every account's vault stay
/// the ciphertext they already are, and open afterwards with what opened them
/// before. A SQLite-backed Quark writes them to the drive; on PostgreSQL they
/// are in the operator's database backup, not the snapshot (#2963). The app
/// cannot tell which, so the copy names both.
class SnapshotBackupDialog extends StatelessWidget {
  const SnapshotBackupDialog({required this.targetName, super.key});

  /// The backup drive's name; empty reads as "this drive".
  final String targetName;

  @override
  Widget build(BuildContext context) {
    return QuarkWidget.alertDialog(
      title: const Text('Snapshot Backup'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Back up all devices to ${targetName.isNotEmpty ? targetName : "this drive"}.',
          ),
          const SizedBox(height: 16),
          const Text(
            "Chat and every account's vault are backed up still encrypted: "
            'on this drive when Quark keeps its own database, or in your '
            'PostgreSQL backups when it runs on PostgreSQL.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Start Backup'),
        ),
      ],
    );
  }
}
