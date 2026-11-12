import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/drive_health_controller.dart';
import 'package:quark/services/data_protection_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/storage_devices/backup_drive_runs_section.dart';
import 'package:quark/widgets/storage_devices/backup_progress_card.dart';
import 'package:quark/widgets/storage_devices/data_drive_backup_section.dart';
import 'package:quark/widgets/storage_devices/drive_health_section.dart';
import 'package:quark/widgets/storage_devices/role_badge.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One storage device: identity, usage bar, category chips, its backup
/// state, and the actions that apply to it. A null callback hides its
/// button.
///
/// A data drive shows [dataDrive]'s chip. A backup drive shows what
/// [backupDrive] holds, its [schedule] ("Backs up weekly."), its backups
/// when [showBackupRuns], and [backupStatus] while a backup onto it runs.
/// Neither carries a protection level: that is the whole Quark's, on the
/// protection card.
class DeviceCard extends StatelessWidget {
  const DeviceCard({
    required this.device,
    required this.isMounting,
    this.onMount,
    this.onSetRole,
    this.onBackup,
    this.onVerify,
    this.onRestore,
    this.onRestoreChat,
    this.onRestoreFiles,
    this.onEject,
    this.isEjecting = false,
    this.isBackupRunning = false,
    this.dataDrive,
    this.backupDrive,
    this.backupStatus,
    this.showBackupRuns = false,
    this.backupRuns,
    this.backupRunsError,
    this.onDeleteRun,
    this.schedule,
    this.onSchedule,
    super.key,
  });

  final StorageDevice device;
  final bool isMounting;
  final VoidCallback? onMount;
  final VoidCallback? onSetRole;
  final VoidCallback? onBackup;
  final VoidCallback? onVerify;

  /// Restores every vault from this snapshot-backup drive. Null hides the
  /// button. Disabled while a backup is running, as [onVerify] is.
  final VoidCallback? onRestore;

  /// Restores the chat from this snapshot-backup drive. Null hides the
  /// button; disabled while a backup is running.
  final VoidCallback? onRestoreChat;

  /// Restores the files on this snapshot-backup drive to the drives they
  /// came from. Null hides the button; disabled while a backup is running.
  final VoidCallback? onRestoreFiles;

  /// Unmounts a plugged-in drive so it can be unplugged. Shown only for an
  /// enabled external drive, and disabled while a backup runs.
  final VoidCallback? onEject;

  /// Whether this drive's eject is in flight.
  final bool isEjecting;

  /// Whether a backup is running, which disables the backup, verify,
  /// restore, and eject buttons.
  final bool isBackupRunning;

  /// This drive's copies, when it holds files. Null draws no chip.
  final DataProtectionDataDrive? dataDrive;

  /// What this drive holds, when it is a backup drive. Null draws nothing.
  final DataProtectionBackupDrive? backupDrive;

  /// The backup running onto this drive. Null draws no progress.
  final BackupJobStatus? backupStatus;

  /// Whether to draw this backup drive's backups, from [backupRuns].
  final bool showBackupRuns;

  /// This backup drive's backups, newest first. Null while they are listed.
  final List<BackupRun>? backupRuns;

  /// The thrown object from a failed listing of [backupRuns].
  final Object? backupRunsError;

  /// Deletes one of [backupRuns], by folder. Null draws no delete action.
  final ValueChanged<String>? onDeleteRun;

  /// This backup drive's schedule, said under what it holds when it is on.
  /// Null draws nothing.
  final BackupSchedule? schedule;

  /// Opens this backup drive's schedule. Null hides the Schedule button,
  /// keyed `device_card_schedule_<serial>`.
  final VoidCallback? onSchedule;

  static const _categoryColors = <String, Color>{
    'documents': Color(0xFF4A90D9),
    'media': Color(0xFF7CB342),
    'backups': Color(0xFFFF8F00),
    'other': Color(0xFF9E9E9E),
    'system': Color(0xFFAB47BC),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usedPct = device.usedPercent.clamp(0.0, 100.0) / 100.0;
    final dataDrive = this.dataDrive;
    final backupDrive = this.backupDrive;
    final backupStatus = this.backupStatus;
    final schedule = this.schedule;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  device.isInternal
                      ? QuarkIcons.computer_outlined
                      : QuarkIcons.usb_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                // A wrap, so at large text the badges drop under the name
                // instead of pushing the row off the card (#2606).
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        device.name.isNotEmpty
                            ? device.name
                            : device.mountPoint,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (device.role != 'unassigned')
                        RoleBadge(role: device.role),
                      if (device.role == 'unassigned' && device.isEnabled)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Enabled',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade800,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // What this drive is, in the words a household uses. The mount
            // point and filesystem below are the same facts for whoever
            // needs them, but they are not what the card leads with (#2047).
            Text(
              key: const ValueKey('device_card_kind'),
              device.isInternal ? 'Inside your Quark' : 'Plugged-in drive',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 2),

            if (device.isUnmounted) ...[
              Text(
                key: const ValueKey('device_card_safe_to_remove'),
                'Not mounted · safe to unplug',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
            ],

            Text(
              '${device.mountPoint}  ·  ${device.fileSystem}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (device.model.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                device.model,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],

            const SizedBox(height: 8),
            DriveHealthSection(
              health: DriveHealthController.view(device.health),
              id: DriveHealthController.idFor(device),
            ),

            if (dataDrive != null) ...[
              const SizedBox(height: 8),
              DataDriveBackupSection(
                drive: dataDrive,
                id: DriveHealthController.idFor(device),
              ),
            ],
            if (backupDrive != null) ...[
              const SizedBox(height: 8),
              Text(
                key: ValueKey('device_card_holds_${device.serial}'),
                _holdsText(backupDrive, MaterialLocalizations.of(context)),
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (schedule != null && schedule.cadence != BackupCadence.off) ...[
              const SizedBox(height: 4),
              Text(
                key: ValueKey('device_card_schedule_text_${device.serial}'),
                'Backs up ${schedule.cadence.name}.'
                '${schedule.waitingForDrive ? ' Due, will run when plugged in.' : ''}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (showBackupRuns) ...[
              const SizedBox(height: 4),
              BackupDriveRunsSection(
                id: DriveHealthController.idFor(device),
                runs: backupRuns,
                error: backupRunsError,
                onDelete: onDeleteRun,
              ),
            ],
            if (backupStatus != null) ...[
              const SizedBox(height: 8),
              BackupProgressCard(status: backupStatus, targetName: device.name),
            ],

            if (device.totalBytes > 0) ...[
              const SizedBox(height: 12),
              QuarkStorageBar(usedFraction: usedPct),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  children: [
                    Text(device.usedDisplay, style: theme.textTheme.bodySmall),
                    Text(
                      '${device.usedPercent.toStringAsFixed(0)}% used',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (device.categories.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: device.categories.entries.map((entry) {
                  final color =
                      _categoryColors[entry.key] ?? const Color(0xFF9E9E9E);
                  return Chip(
                    avatar: CircleAvatar(backgroundColor: color, radius: 6),
                    label: Text(
                      '${_capitalize(entry.key)} · ${StorageDevice.formatBytes(entry.value)}',
                    ),
                    labelStyle: theme.textTheme.bodySmall,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    // A label with no tap of its own, so shrinking it takes
                    // nothing from a touch target (#2939).
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],

            if (!device.isEnabled && onMount != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: isMounting ? null : onMount,
                icon: isMounting
                    ? const QuarkLoader(size: 14)
                    : const Icon(QuarkIcons.link_outlined, size: 16),
                label: Text(isMounting ? 'Mounting…' : 'Mount'),
              ),
            ],

            // Role + backup actions for enabled external devices, and the
            // role alone for built-in storage (#3194)
            if (device.isEnabled &&
                (!device.isInternal || onSetRole != null)) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onSetRole != null)
                    OutlinedButton.icon(
                      onPressed: onSetRole,
                      icon: const Icon(QuarkIcons.label_outline, size: 16),
                      label: const Text('Set Role'),
                    ),
                  if (onBackup != null)
                    FilledButton.icon(
                      onPressed: isBackupRunning ? null : onBackup,
                      icon: const Icon(QuarkIcons.backup_outlined, size: 16),
                      label: const Text('Back up onto this drive'),
                    ),
                  if (onSchedule != null)
                    OutlinedButton.icon(
                      key: ValueKey('device_card_schedule_${device.serial}'),
                      onPressed: onSchedule,
                      icon: const Icon(QuarkIcons.schedule_rounded, size: 16),
                      label: const Text('Schedule'),
                    ),
                  if (onVerify != null)
                    OutlinedButton.icon(
                      onPressed: isBackupRunning ? null : onVerify,
                      icon: const Icon(QuarkIcons.verified_outlined, size: 16),
                      label: const Text('Verify'),
                    ),
                  if (onRestore != null)
                    OutlinedButton.icon(
                      key: ValueKey('device_card_restore_${device.serial}'),
                      onPressed: isBackupRunning ? null : onRestore,
                      icon: const Icon(QuarkIcons.restore, size: 16),
                      label: const Text('Restore vaults'),
                    ),
                  if (onRestoreChat != null)
                    OutlinedButton.icon(
                      key: ValueKey(
                        'device_card_restore_chat_${device.serial}',
                      ),
                      onPressed: isBackupRunning ? null : onRestoreChat,
                      icon: const Icon(QuarkIcons.restore, size: 16),
                      label: const Text('Restore chat'),
                    ),
                  if (onRestoreFiles != null)
                    OutlinedButton.icon(
                      key: ValueKey(
                        'device_card_restore_files_${device.serial}',
                      ),
                      onPressed: isBackupRunning ? null : onRestoreFiles,
                      icon: const Icon(QuarkIcons.restore, size: 16),
                      label: const Text('Restore files'),
                    ),
                  if (!device.isInternal && onEject != null)
                    OutlinedButton.icon(
                      key: ValueKey('device_card_eject_${device.serial}'),
                      onPressed: isEjecting || isBackupRunning ? null : onEject,
                      icon: isEjecting
                          ? const QuarkLoader(size: 14)
                          : const Icon(QuarkIcons.eject_outlined, size: 16),
                      label: Text(isEjecting ? 'Ejecting…' : 'Eject'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "Holds copies of Built-in storage, Photos. Newest Nov 2.", or "No
  /// copies yet.", and what to do about a behind or retired drive.
  static String _holdsText(
    DataProtectionBackupDrive drive,
    MaterialLocalizations localizations,
  ) {
    final newest = drive.newestCopy;
    final holds = drive.holds.isEmpty || newest == null
        ? 'No copies yet.'
        : 'Holds copies of ${drive.holds.map((h) => h.name).join(', ')}. '
              'Newest ${localizations.formatShortMonthDay(newest.toLocal())}.';
    final next = switch (drive.state) {
      DataProtectionBackupState.behind =>
        ' Back up onto this drive to bring it up to date.',
      DataProtectionBackupState.retired =>
        ' Replace this drive soon. Its copies no longer count.',
      _ => '',
    };
    return holds + next;
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
