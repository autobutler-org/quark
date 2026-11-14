import 'package:material_ui/material_ui.dart';

import '../../core/quark_progress_row.dart';
import '../../models/upload_item.dart';
import '../../theme/quark_tokens.dart';

/// One upload in a `JobList`, drawn as a `QuarkProgressRow`: the file's name
/// and destination, how much has arrived, the rate and time left while it
/// moves, a progress bar while it is in flight, and a Cancel action when
/// [UploadItem] offers one.
///
/// Key prefixes: `upload_row_<id>` on the row, `upload_cancel_<id>` on Cancel.
class UploadRow extends StatelessWidget {
  /// Creates the row for [item].
  const UploadRow({required this.item, this.onCancel, super.key});

  /// The upload to draw.
  final UploadItem item;

  /// Called with [UploadItem.id] when Cancel is tapped.
  final ValueChanged<String>? onCancel;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final inFlight = switch (item.status) {
      UploadItemStatus.uploading ||
      UploadItemStatus.finishing ||
      UploadItemStatus.stalled => true,
      _ => false,
    };
    final statusColor = switch (item.status) {
      UploadItemStatus.failed ||
      UploadItemStatus.expired ||
      UploadItemStatus.stalled => tokens.error,
      UploadItemStatus.completed => tokens.success,
      _ => tokens.mutedForeground,
    };
    final rate = item.bytesPerSecond;
    final remaining = item.remaining;
    final moving = item.status == UploadItemStatus.uploading;
    final details = [
      _statusLabel(item.status),
      if (item.status == UploadItemStatus.completed)
        formatBytes(item.totalBytes)
      else
        '${formatBytes(item.sentBytes)} of ${formatBytes(item.totalBytes)}',
      if (moving && rate != null && rate > 0) '${formatBytes(rate.round())}/s',
      if (moving && remaining != null) formatRemaining(remaining),
    ].join(' · ');
    final fraction = item.totalBytes <= 0
        ? 0.0
        : item.sentBytes / item.totalBytes;

    return QuarkProgressRow(
      key: ValueKey('upload_row_${item.id}'),
      title: item.fileName,
      subtitle: item.destination,
      status: details,
      statusColor: statusColor,
      progress: inFlight ? fraction : null,
      actions: [
        if (item.canCancel)
          TextButton(
            key: ValueKey('upload_cancel_${item.id}'),
            onPressed: onCancel == null ? null : () => onCancel!(item.id),
            child: const Text('Cancel'),
          ),
      ],
    );
  }
}

String _statusLabel(UploadItemStatus status) => switch (status) {
  UploadItemStatus.uploading => 'Uploading',
  UploadItemStatus.finishing => 'Finishing',
  UploadItemStatus.stalled => 'Stalled',
  UploadItemStatus.completed => 'Uploaded',
  UploadItemStatus.failed => 'Failed',
  UploadItemStatus.canceled => 'Canceled',
  UploadItemStatus.expired => 'Timed out',
};

/// `512 B`, `1.5 KB`, `12 MB`, `2.3 GB`: one decimal below ten, none above.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes < 0 ? 0.0 : bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 10 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// `Under a minute left`, `About 5 min left`, `About 2 h 10 min left`.
String formatRemaining(Duration remaining) {
  final minutes = (remaining.inSeconds / 60).ceil();
  if (minutes <= 1) return 'Under a minute left';
  if (minutes < 60) return 'About $minutes min left';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? 'About $h h left' : 'About $h h $m min left';
}
