import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/quark_loader.dart';
import '../models/backup_run_item.dart';
import '../theme/quark_tokens.dart';

/// The backups on a backup drive, on its drive card: one line that reads
/// [summary] ("3 backups · newest Nov 2") and opens to one row per run, with
/// its time, its size, the drives it holds, and a delete action.
///
/// Expansion is [expanded]; [onExpandedChanged] reports a tap on the summary
/// with the next open state. With no [runs] the summary is a plain line.
/// [isLoading] draws a loader while there are no runs to show, and [error]
/// replaces the rows with the caller's sentence. A null [onDelete] draws no
/// delete action.
///
/// Key prefixes: `backup_runs_<id>` on the summary, `backup_run_<id>_<index>`
/// on each row, and `backup_run_delete_<id>_<index>` on its delete action.
///
/// ```dart
/// BackupRunsList(
///   id: 'USB2',
///   summary: '2 backups · newest Nov 2',
///   runs: const [
///     BackupRunItem(id: '2026-11-02 09.00', time: 'Nov 2, 09.00',
///         size: '1.2 GB', drives: 'Built-in storage'),
///   ],
///   expanded: false,
///   onExpandedChanged: (open) {},
///   onDelete: (run) {},
/// )
/// ```
class BackupRunsList extends StatelessWidget {
  /// Creates the list for the drive keyed [id].
  const BackupRunsList({
    required this.id,
    required this.summary,
    required this.runs,
    required this.expanded,
    required this.onExpandedChanged,
    this.onDelete,
    this.isLoading = false,
    this.error,
    super.key,
  });

  /// Distinguishes this drive's keys from the others on the page.
  final String id;

  /// The words on the collapsed line.
  final String summary;

  /// The runs, newest first.
  final List<BackupRunItem> runs;

  /// Whether the rows are open.
  final bool expanded;

  /// Called with the next open state when the summary is tapped.
  final ValueChanged<bool> onExpandedChanged;

  /// Called with a run's [BackupRunItem.id] when its delete action is
  /// tapped. Null draws no delete action.
  final ValueChanged<String>? onDelete;

  /// Whether the runs are still being listed.
  final bool isLoading;

  /// Why the runs could not be listed, in the caller's words. Null is no
  /// error.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: tokens.secondaryForeground,
    );
    final error = this.error;
    final onDelete = this.onDelete;
    final label = Text(summary, style: theme.textTheme.bodyMedium);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error != null)
          Text(
            error,
            key: ValueKey('backup_runs_error_$id'),
            style: theme.textTheme.bodySmall?.copyWith(color: tokens.error),
          )
        else if (isLoading && runs.isEmpty)
          const QuarkLoader(size: 16)
        else if (runs.isEmpty)
          KeyedSubtree(key: ValueKey('backup_runs_$id'), child: label)
        else
          TextButton(
            key: ValueKey('backup_runs_$id'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: tokens.spacingXs),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.padded,
              alignment: Alignment.centerLeft,
            ),
            onPressed: () => onExpandedChanged(!expanded),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: label),
                Icon(
                  expanded ? QuarkIcons.expand_less : QuarkIcons.expand_more,
                  size: 18,
                ),
              ],
            ),
          ),
        if (expanded && error == null)
          for (var i = 0; i < runs.length; i++)
            Padding(
              key: ValueKey('backup_run_${id}_$i'),
              padding: EdgeInsets.only(top: tokens.spacingXs),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(runs[i].time, style: theme.textTheme.bodyMedium),
                        if (runs[i].size.isNotEmpty ||
                            runs[i].drives.isNotEmpty)
                          Text(
                            [
                              runs[i].size,
                              runs[i].drives,
                            ].where((part) => part.isNotEmpty).join(' · '),
                            style: secondary,
                          ),
                      ],
                    ),
                  ),
                  if (onDelete != null)
                    IconButton(
                      key: ValueKey('backup_run_delete_${id}_$i'),
                      tooltip: 'Delete backup',
                      icon: const Icon(QuarkIcons.delete_outline, size: 20),
                      onPressed: () => onDelete(runs[i].id),
                    ),
                ],
              ),
            ),
      ],
    );
  }
}
