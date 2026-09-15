import 'package:flutter/material.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/storage_devices/backup_progress_card.dart';
import 'package:quark/widgets/storage_devices/device_card.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Body of the devices page: no host, error, spinner, or the device list with
/// the backup progress card on top.
class StorageDevicesBody extends StatelessWidget {
  const StorageDevicesBody({
    required this.devices,
    required this.error,
    required this.mounting,
    required this.vaultDeviceSerial,
    required this.backupStatus,
    required this.activeBackupJobId,
    required this.onRefresh,
    required this.onRetry,
    required this.onManageHosts,
    this.onMount,
    this.onSetRole,
    this.onBackup,
    this.onVerify,
    super.key,
  });

  /// Null while the first listing is still in flight.
  final List<StorageDevice>? devices;

  /// The thrown object, not its message — the render decides whether it means
  /// "your Quark is unreachable" or "the request failed" (#1637).
  final Object? error;

  /// Serials whose mount is in progress.
  final Set<String> mounting;
  final String vaultDeviceSerial;
  final BackupJobStatus? backupStatus;
  final String? activeBackupJobId;
  final RefreshCallback onRefresh;
  final VoidCallback onRetry;
  final VoidCallback onManageHosts;

  /// The drive actions. Each is admin-only on the Quark, so the page leaves
  /// them null for anyone else, and a null one draws no button (#1928).
  final ValueChanged<StorageDevice>? onMount;
  final ValueChanged<StorageDevice>? onSetRole;
  final ValueChanged<StorageDevice>? onBackup;
  final ValueChanged<StorageDevice>? onVerify;

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
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }
    final devices = this.devices;
    if (devices == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (devices.isEmpty) {
      return const Center(child: Text('No storage devices detected.'));
    }
    final widgets = <Widget>[];

    if (backupStatus != null && activeBackupJobId != null) {
      widgets.add(BackupProgressCard(status: backupStatus!));
    }

    final onMount = this.onMount;
    final onSetRole = this.onSetRole;
    final onBackup = this.onBackup;
    final onVerify = this.onVerify;
    for (final device in devices) {
      final isVaultDevice =
          (vaultDeviceSerial.isEmpty && device.isInternal) ||
          (vaultDeviceSerial.isNotEmpty && device.serial == vaultDeviceSerial);
      final isUsb = device.serial.isNotEmpty;
      final isBackupDrive = device.role == 'snapshot-backup';
      widgets.add(
        DeviceCard(
          device: device,
          isMounting: mounting.contains(device.serial),
          isVaultDevice: isVaultDevice,
          onMount: onMount != null && isUsb ? () => onMount(device) : null,
          onSetRole: onSetRole != null && isUsb
              ? () => onSetRole(device)
              : null,
          onBackup: onBackup != null && isBackupDrive
              ? () => onBackup(device)
              : null,
          onVerify: onVerify != null && isBackupDrive
              ? () => onVerify(device)
              : null,
          isBackupRunning: backupStatus?.isRunning == true,
        ),
      );
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
