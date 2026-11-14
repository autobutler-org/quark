import 'package:material_ui/material_ui.dart';

import '../../core/quark_progress_row.dart';
import '../../models/job_item.dart';
import '../../theme/quark_tokens.dart';

/// One job in a `JobList`, drawn as a `QuarkProgressRow`: its name, a status
/// line, a progress bar while it runs, and a Cancel or Retry action when
/// [JobItem] offers one.
///
/// Key prefixes: `job_row_<id>` on the row, `job_cancel_<id>` and
/// `job_retry_<id>` on the actions.
class JobRow extends StatelessWidget {
  /// Creates the row for [item].
  const JobRow({required this.item, this.onCancel, this.onRetry, super.key});

  /// The job to draw.
  final JobItem item;

  /// Called with [JobItem.id] when Cancel is tapped.
  final ValueChanged<int>? onCancel;

  /// Called with [JobItem.id] when Retry is tapped.
  final ValueChanged<int>? onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final statusColor = switch (item.status) {
      JobItemStatus.failed => tokens.error,
      JobItemStatus.completed => tokens.success,
      _ => tokens.mutedForeground,
    };
    final elapsed = item.elapsed;
    final details = [
      _statusLabel(item.status),
      if (item.status == JobItemStatus.running)
        '${(item.progress.clamp(0, 1) * 100).round()}%',
      if (elapsed != null) _formatElapsed(elapsed),
      if (item.attempts > 1) 'Attempt ${item.attempts}',
      if (item.isQuickCopy) 'Quick copy',
    ].join(' · ');

    return QuarkProgressRow(
      key: ValueKey('job_row_${item.id}'),
      title: item.name,
      status: details,
      statusColor: statusColor,
      progress: item.status == JobItemStatus.running ? item.progress : null,
      actions: [
        if (item.canCancel)
          TextButton(
            key: ValueKey('job_cancel_${item.id}'),
            onPressed: onCancel == null ? null : () => onCancel!(item.id),
            child: const Text('Cancel'),
          ),
        if (item.canRetry)
          TextButton(
            key: ValueKey('job_retry_${item.id}'),
            onPressed: onRetry == null ? null : () => onRetry!(item.id),
            child: const Text('Retry'),
          ),
      ],
    );
  }
}

String _statusLabel(JobItemStatus status) => switch (status) {
  JobItemStatus.pending => 'Queued',
  JobItemStatus.running => 'Running',
  JobItemStatus.completed => 'Completed',
  JobItemStatus.failed => 'Failed',
  JobItemStatus.canceled => 'Canceled',
  JobItemStatus.unknown => 'Unknown',
};

/// `0:07`, `12:34`, or `1:02:03`.
String _formatElapsed(Duration elapsed) {
  final seconds = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}
