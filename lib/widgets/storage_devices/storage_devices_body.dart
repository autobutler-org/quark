import 'package:flutter/material.dart';
import 'package:quark/controllers/backup_runs_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/data_protection_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/storage_devices/device_card.dart';
import 'package:quark/widgets/storage_devices/restore_files_flow.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Body of the devices page: no host, error, spinner, or the device list.
///
/// [header] is drawn above that list. Each drive card shows its own backup
/// state from [protection]: a data drive its copies, a backup drive what it
/// holds and, from [backupStatuses], the backup running onto it.
/// [onRestore], like backup and verify, is drawn only
/// on a drive with the snapshot-backup role, and only when the page passes it.
/// **Restore files** shows wherever [onRestore] does: it is admin-only too,
/// and [onRestoreFiles] defaults to [restoreFilesFrom], offering the drive's
/// runs from [backupRuns]. A backup drive lists its backups when
/// [backupRuns] is set, and [onDeleteRun] deletes one.
class StorageDevicesBody extends StatelessWidget {
  const StorageDevicesBody({
    required this.devices,
    required this.error,
    required this.mounting,
    required this.onRefresh,
    required this.onRetry,
    required this.onManageHosts,
    this.onMount,
    this.onSetRole,
    this.onBackup,
    this.onVerify,
    this.onRestore,
    this.onRestoreFiles,
    this.onEject,
    this.ejecting = const {},
    this.header,
    this.protection,
    this.backupStatuses = const {},
    this.isBackupRunning = false,
    this.backupRuns,
    this.onDeleteRun,
    super.key,
  });

  /// Null while the first listing is still in flight.
  final List<StorageDevice>? devices;

  /// The thrown object, not its message — the render decides whether it means
  /// "your Quark is unreachable" or "the request failed" (#1637).
  final Object? error;

  /// Serials whose mount is in progress.
  final Set<String> mounting;
  final RefreshCallback onRefresh;
  final VoidCallback onRetry;
  final VoidCallback onManageHosts;

  /// The drive actions. Each is admin-only on the Quark, so the page leaves
  /// them null for anyone else, and a null one draws no button (#1928).
  final ValueChanged<StorageDevice>? onMount;
  final ValueChanged<StorageDevice>? onSetRole;
  final ValueChanged<StorageDevice>? onBackup;
  final ValueChanged<StorageDevice>? onVerify;

  /// Restores vaults from a snapshot-backup drive. Null draws no button, and
  /// a drive with any other role draws none either.
  final ValueChanged<StorageDevice>? onRestore;

  /// Restores a snapshot-backup drive's files. Used only where [onRestore]
  /// is set; null there means [restoreFilesFrom].
  final ValueChanged<StorageDevice>? onRestoreFiles;
  final ValueChanged<StorageDevice>? onEject;

  /// Serials whose eject is in progress.
  final Set<String> ejecting;

  /// Drawn above the drive list. Null leaves the list as it was.
  final Widget? header;

  /// Each drive's copies and holdings. Null draws no backup state.
  final DataProtectionStatus? protection;

  /// The running backup onto each backup drive, by serial.
  final Map<String, BackupJobStatus> backupStatuses;

  /// Whether any backup is running, which disables the backup, verify,
  /// restore, and eject buttons on every card, and hides delete on every
  /// backup.
  final bool isBackupRunning;

  /// Each backup drive's backups. Null draws none: listing them is
  /// admin-only on the Quark.
  final BackupRunsController? backupRuns;

  /// Deletes a backup, by folder, from a backup drive. Null draws no delete
  /// action.
  final void Function(StorageDevice device, String run)? onDeleteRun;

  @override
  Widget build(BuildContext context) {
    if (AppSettings.instance.activeHost == null) {
      return const Center(child: Text('No quark host configured.'));
    }
    final error = this.error;
    if (error != null) {
      if (isQuarkUnreachableError(error)) {
        return QuarkDisconnectedView(
          hostAddress: AppSettings.instance.activeHost,
          onRetry: onRetry,
          onManageHosts: onManageHosts,
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            Errors.message(error, 'load your drives'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    final devices = this.devices;
    if (devices == null) {
      return const Center(child: QuarkLoader());
    }
    final header = this.header;
    if (devices.isEmpty && header == null) {
      return const Center(child: Text('No storage devices detected.'));
    }
    final widgets = <Widget>[?header];

    final onMount = this.onMount;
    final onSetRole = this.onSetRole;
    final onBackup = this.onBackup;
    final onVerify = this.onVerify;
    final onRestore = this.onRestore;
    final backupRuns = this.backupRuns;
    final onRestoreFiles =
        this.onRestoreFiles ??
        (device) => restoreFilesFrom(
          context,
          device,
          runs: backupRuns?.runsFor(device.serial) ?? const [],
        );
    final onEject = this.onEject;
    final onDeleteRun = isBackupRunning ? null : this.onDeleteRun;
    for (final device in devices) {
      final isUsb = device.serial.isNotEmpty;
      final isBackupDrive = device.role == 'snapshot-backup';
      // An empty serial is built-in storage's alone; a USB drive the Quark
      // could not read a serial from is not matched to it.
      final protection = isUsb || device.isInternal ? this.protection : null;
      widgets.add(
        DeviceCard(
          device: device,
          isMounting: mounting.contains(device.serial),
          onMount: onMount != null && isUsb ? () => onMount(device) : null,
          // Built-in storage too: it can take default storage back (#3194).
          onSetRole: onSetRole != null && (isUsb || device.isInternal)
              ? () => onSetRole(device)
              : null,
          onBackup: onBackup != null && isBackupDrive
              ? () => onBackup(device)
              : null,
          onVerify: onVerify != null && isBackupDrive
              ? () => onVerify(device)
              : null,
          onRestore: onRestore != null && isBackupDrive
              ? () => onRestore(device)
              : null,
          onRestoreFiles: onRestore != null && isBackupDrive
              ? () => onRestoreFiles(device)
              : null,
          onEject: onEject != null && isUsb ? () => onEject(device) : null,
          isEjecting: ejecting.contains(device.serial),
          isBackupRunning: isBackupRunning,
          dataDrive: isBackupDrive
              ? null
              : protection?.dataDrive(device.serial),
          backupDrive: isBackupDrive
              ? protection?.backupDrive(device.serial)
              : null,
          backupStatus: isBackupDrive ? backupStatuses[device.serial] : null,
          showBackupRuns:
              isBackupDrive && device.isEnabled && backupRuns != null,
          backupRuns: backupRuns?.runsFor(device.serial),
          backupRunsError: backupRuns?.errorFor(device.serial),
          onDeleteRun: onDeleteRun != null && isBackupDrive
              ? (run) => onDeleteRun(device, run)
              : null,
        ),
      );
    }
    if (devices.isEmpty) {
      widgets.add(const Center(child: Text('No storage devices detected.')));
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: widgets.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, i) => widgets[i],
      ),
    );
  }
}
