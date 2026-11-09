import 'package:flutter/material.dart';
import 'package:quark/utils/quark_widget.dart';

/// Confirms a snapshot backup that copies the data drives named
/// [sourceNames] onto the backup drive named [targetName]. Pops with `true`
/// on Start Backup, or with nothing on Cancel.
///
/// It asks for no password (#3460): the chat and every account's vault stay
/// the ciphertext they already are, and open afterwards with what opened them
/// before. A SQLite-backed Quark writes them to the drive; on PostgreSQL they
/// are in the operator's database backup, not the snapshot (#2963). The app
/// cannot tell which, so the copy names both.
class SnapshotBackupDialog extends StatelessWidget {
  const SnapshotBackupDialog({
    required this.targetName,
    required this.sourceNames,
    super.key,
  });

  /// The backup drive's name; empty reads as "this drive".
  final String targetName;

  /// The data drives the backup copies; none reads as "your other drives".
  final List<String> sourceNames;

  /// Joins [names] the way a sentence does: "A", "A and B", "A, B and C".
  static String _list(List<String> names) => switch (names.length) {
    0 => 'your other drives',
    1 => names.first,
    _ => '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
  };

  @override
  Widget build(BuildContext context) {
    return QuarkWidget.alertDialog(
      title: const Text('Back up onto this drive'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Copy ${_list(sourceNames)} onto '
            '${targetName.isNotEmpty ? targetName : "this drive"}.',
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
