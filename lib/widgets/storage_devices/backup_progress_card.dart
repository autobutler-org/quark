import 'package:material_ui/material_ui.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark_icons/quark_icons.dart';

/// Progress of a backup running onto one backup drive, drawn on that drive's
/// card: "Copying Built-in storage onto Backup A · 42%".
///
/// The source is [BackupJobStatus.currentSource], or every source when the
/// Quark has not started one yet. The target is [BackupJobStatus.targetName],
/// or [targetName] when the Quark did not send one. The page drops the
/// status once the backup finishes, so only a running backup is drawn.
class BackupProgressCard extends StatelessWidget {
  /// Creates the progress for [status] onto the drive named [targetName].
  const BackupProgressCard({
    required this.status,
    required this.targetName,
    super.key,
  });

  /// The running backup.
  final BackupJobStatus status;

  /// The card's drive name, used when [status] carries none.
  final String targetName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (status.progress * 100).toStringAsFixed(0);
    final target = status.targetName ?? targetName;
    final sources = status.currentSource ?? status.sourceNames.join(', ');
    final what = sources.isEmpty ? '' : ' $sources';

    final statusText = switch (status.status) {
      'PENDING' => 'Preparing to back up onto $target',
      'SCANNING' => 'Scanning$what',
      _ => 'Copying$what onto $target · $pct%',
    };

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(QuarkIcons.backup_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusText,
                    key: const ValueKey('backup_progress_text'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: status.progress),
            const SizedBox(height: 8),
            Text(
              '${status.filesCopied} / ${status.totalFiles} files  ·  '
              '${StorageDevice.formatBytes(status.bytesCopied)} / '
              '${StorageDevice.formatBytes(status.totalBytes)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
