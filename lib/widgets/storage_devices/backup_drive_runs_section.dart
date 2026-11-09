import 'package:flutter/material.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/backup_run_label.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The backups on a backup drive's card (#4044): "3 backups · newest Nov 2",
/// opening to one row per run with a delete action.
///
/// The wording is built here from [runs]; expansion stays here too, closed
/// at first.
class BackupDriveRunsSection extends StatefulWidget {
  /// Creates the section for the drive keyed [id].
  const BackupDriveRunsSection({
    required this.id,
    required this.runs,
    this.error,
    this.onDelete,
    super.key,
  });

  /// Distinguishes this drive's keys from the others on the page.
  final String id;

  /// The drive's runs, newest first. Null while they are being listed.
  final List<BackupRun>? runs;

  /// The thrown object from a failed listing. Null is no error.
  final Object? error;

  /// Called with a run's folder when its delete action is tapped. Null draws
  /// no delete action.
  final ValueChanged<String>? onDelete;

  @override
  State<BackupDriveRunsSection> createState() => _BackupDriveRunsSectionState();
}

class _BackupDriveRunsSectionState extends State<BackupDriveRunsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final runs = widget.runs ?? const [];
    final error = widget.error;
    final newest = runs.firstOrNull;
    final newestAt = newest?.completedAt;
    final newestDay = newestAt == null
        ? null
        : MaterialLocalizations.of(
            context,
          ).formatShortMonthDay(newestAt.toLocal());
    final count = runs.length == 1 ? '1 backup' : '${runs.length} backups';
    return BackupRunsList(
      id: widget.id,
      summary: switch ((newest, newestDay)) {
        (null, _) => 'No backups yet',
        (_, null) => count,
        (_, final day?) => '$count · newest $day',
      },
      runs: [for (final run in runs) backupRunItem(run)],
      expanded: _expanded,
      onExpandedChanged: (open) => setState(() => _expanded = open),
      onDelete: widget.onDelete,
      isLoading: widget.runs == null && error == null,
      error: error == null ? null : Errors.message(error, 'list the backups'),
    );
  }
}
