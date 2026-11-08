import 'package:flutter/material.dart';

import '../models/backup_run_item.dart';
import '../theme/quark_tokens.dart';

/// Which backup a restore reads, in a restore dialog: a sentence naming the
/// [selected] run ("From the backup of Nov 2, 09.00.") and, when the drive
/// holds more than one, a menu of [runs] to pick another.
///
/// [onSelected] reports the picked run's [BackupRunItem.id]; the caller
/// passes it back as [selected].
///
/// Key prefixes: `backup_run_picker_label` on the sentence,
/// `backup_run_picker` on the menu, and `backup_run_picker_<index>` on each
/// of its items.
///
/// ```dart
/// BackupRunPicker(
///   runs: runs,
///   selected: runs.first.id,
///   onSelected: (run) {},
/// )
/// ```
class BackupRunPicker extends StatelessWidget {
  /// Creates the picker. [selected] must be the id of one of [runs].
  const BackupRunPicker({
    required this.runs,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// The runs on the drive, newest first. Not empty.
  final List<BackupRunItem> runs;

  /// The id of the run the restore reads.
  final String selected;

  /// Called with the id of the run picked from the menu.
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final run = runs.firstWhere(
      (r) => r.id == selected,
      orElse: () => runs.first,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'From the backup of ${run.time}.',
          key: const ValueKey('backup_run_picker_label'),
        ),
        if (runs.length > 1) ...[
          SizedBox(height: tokens.spacingSm),
          DropdownButtonFormField<String>(
            key: const ValueKey('backup_run_picker'),
            initialValue: run.id,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Backup',
              border: OutlineInputBorder(),
            ),
            items: [
              for (var i = 0; i < runs.length; i++)
                DropdownMenuItem(
                  key: ValueKey('backup_run_picker_$i'),
                  value: runs[i].id,
                  child: Text(
                    [
                      runs[i].time,
                      runs[i].size,
                    ].where((part) => part.isNotEmpty).join(' · '),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) {
              if (id != null) onSelected(id);
            },
          ),
        ],
      ],
    );
  }
}
