import 'package:flutter/material.dart';
import 'package:quark/services/vault_backup_service.dart';

/// What a restore from a backup drive did (#1665): entries and folders
/// restored, and the ones already in the vault that were left unchanged.
///
/// A restore never overwrites, so an entry that conflicts with one in the
/// vault is a skipped one. A count of zero says nothing, except that a
/// restore which added no entries says so. Key: `vault_restore_summary`.
///
/// ```dart
/// VaultRestoreSummary(result: controller.result!)
/// ```
class VaultRestoreSummary extends StatelessWidget {
  /// The counts the Quark reported.
  final VaultRestoreResult result;

  const VaultRestoreSummary({super.key, required this.result});

  static String _entries(int n) => n == 1 ? '1 entry' : '$n entries';
  static String _folders(int n) => n == 1 ? '1 folder' : '$n folders';
  static String _were(int n) => n == 1 ? 'was' : 'were';

  @override
  Widget build(BuildContext context) {
    final r = result;
    return Column(
      key: const ValueKey('vault_restore_summary'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(
          r.entriesImported == 0
              ? 'No new entries were restored.'
              : 'Restored ${_entries(r.entriesImported)}.',
        ),
        if (r.entriesSkipped > 0)
          Text(
            '${_entries(r.entriesSkipped)} ${_were(r.entriesSkipped)} already '
            'in your vault and ${_were(r.entriesSkipped)} left unchanged.',
          ),
        if (r.foldersImported > 0)
          Text('Restored ${_folders(r.foldersImported)}.'),
        if (r.foldersSkipped > 0)
          Text(
            '${_folders(r.foldersSkipped)} ${_were(r.foldersSkipped)} already '
            'in your vault.',
          ),
      ],
    );
  }
}
