import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/widgets/storage_devices/backup_source_list.dart';

/// Confirms a snapshot backup onto the backup drive named [targetName] and
/// asks which of the data drives in [sources] it copies (#3984). Every drive
/// starts checked, and Start Backup is off while none is. Pops with the
/// checked serials on Start Backup, or with nothing on Cancel.
///
/// Each drive's checkbox is a [BackupSourceList] key,
/// `backup_source_<serial>`. Start Backup is `snapshot_backup_start`.
///
/// It asks for no password (#3460): the chat and every account's vault stay
/// the ciphertext they already are, and open afterwards with what opened them
/// before. A SQLite-backed Quark writes them to the drive; on PostgreSQL they
/// are in the operator's database backup, not the snapshot (#2963). The app
/// cannot tell which, so the copy names both.
class SnapshotBackupDialog extends StatefulWidget {
  /// Creates the dialog over [sources], serial to name, in display order.
  const SnapshotBackupDialog({
    required this.targetName,
    required this.sources,
    super.key,
  });

  /// The backup drive's name; empty reads as "this drive".
  final String targetName;

  /// The data drives the backup can copy, serial to name.
  final Map<String, String> sources;

  @override
  State<SnapshotBackupDialog> createState() => _SnapshotBackupDialogState();
}

class _SnapshotBackupDialogState extends State<SnapshotBackupDialog> {
  late final Set<String> _checked = widget.sources.keys.toSet();

  @override
  Widget build(BuildContext context) {
    final target = widget.targetName.isNotEmpty
        ? widget.targetName
        : 'this drive';
    return QuarkWidget.alertDialog(
      title: const Text('Back up onto this drive'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Choose the drives to copy onto $target.'),
          BackupSourceList(
            sources: widget.sources,
            checked: _checked,
            onChanged: (serial, checked) => setState(
              () => checked ? _checked.add(serial) : _checked.remove(serial),
            ),
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
          key: const ValueKey('snapshot_backup_start'),
          onPressed: _checked.isEmpty
              ? null
              : () => Navigator.pop(context, [
                  for (final serial in widget.sources.keys)
                    if (_checked.contains(serial)) serial,
                ]),
          child: const Text('Start Backup'),
        ),
      ],
    );
  }
}
