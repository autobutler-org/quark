import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/backup_runs_controller.dart';
import 'package:quark/controllers/data_protection_controller.dart';
import 'package:quark/controllers/drive_health_controller.dart';
import 'package:quark/controllers/restore_vault_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/data_protection_service.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/backup_run_label.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/widgets/layout/admin_map_card.dart';
import 'package:quark/widgets/storage_devices/credentials_dialog.dart';
import 'package:quark/widgets/storage_devices/delete_backup_run_dialog.dart';
import 'package:quark/widgets/storage_devices/eject_drive_dialog.dart';
import 'package:quark/widgets/storage_devices/restore_vault_dialog.dart';
import 'package:quark/widgets/storage_devices/role_dialog.dart';
import 'package:quark/widgets/storage_devices/snapshot_backup_dialog.dart';
import 'package:quark/widgets/storage_devices/storage_devices_body.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The System page's Storage tab: how protected the files are, the drives the
/// Quark can see, their status, role and backup state, and the actions to
/// mount, eject, rename or back up onto them. A backup running onto a drive
/// is found from the device list, so one started elsewhere shows here too.
/// An admin also sees each backup drive's backups and can delete one
/// (#4044), restore the vaults or files from a backup they pick (#4032), and
/// gets the [AdminMapCard] (#2484).
class StorageTab extends StatefulWidget {
  const StorageTab({
    this.onRefreshingChanged,
    this.restoreVault,
    this.events,
    super.key,
  });

  /// Called with whether a refresh is in flight whenever that changes, so
  /// the page's app bar can show it.
  final ValueChanged<bool>? onRefreshingChanged;

  /// The vault restore. Tests pass one; otherwise the tab builds its own.
  final RestoreVaultController? restoreVault;

  /// The Quark's events, which reload the protection status and the backups.
  /// Null is the app's event stream.
  final Stream<FileEvent>? events;

  @override
  State<StorageTab> createState() => _StorageTabState();
}

class _StorageTabState extends State<StorageTab>
    with WidgetsBindingObserver, AutoRefreshMixin {
  List<StorageDevice>? _devices;

  /// The thrown object, not its message — the render decides whether it means
  /// "your Quark is unreachable" or "the request failed" (#1637).
  Object? _error;
  final Set<String> _mounting = {};
  final Set<String> _ejecting = {};

  /// The backup pending or running onto each backup drive, by serial: the
  /// ones the device list reports and the ones this tab started.
  final Map<String, String> _activeJobs = {};

  /// The last status of each job in [_activeJobs], by serial.
  final Map<String, BackupJobStatus> _backupStatuses = {};
  Timer? _pollTimer;
  late final DataProtectionController _protection;
  late final BackupRunsController _runs;
  late final RestoreVaultController _restore;
  late final bool _ownsRestore;

  @override
  void initState() {
    _protection = DataProtectionController(events: widget.events);
    _protection.addListener(_onControllerChanged);
    _runs = BackupRunsController(events: widget.events);
    _runs.addListener(_onControllerChanged);
    _restore = widget.restoreVault ?? RestoreVaultController();
    _ownsRestore = widget.restoreVault == null;
    super.initState();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeRefreshing() => widget.onRefreshingChanged?.call(isRefreshing);

  @override
  Future<void> refresh() async {
    if (AppSettings.instance.activeHost == null) {
      setState(() {
        _devices = null;
        _error = null;
      });
      return;
    }
    final protection = _protection.load();
    try {
      final devices = await StorageService.listDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _error = null;
        for (final device in devices) {
          final jobId = device.activeBackupJobId;
          if (jobId != null) _activeJobs[device.serial] = jobId;
        }
      });
      if (_activeJobs.isNotEmpty) _startPolling();
      // Listing a drive's backups is admin-only on the Quark.
      if (AppSettings.instance.isAdmin.value) {
        unawaited(
          _runs.load([
            for (final device in devices)
              if (device.role == 'snapshot-backup' && device.isEnabled)
                device.serial,
          ]),
        );
      }
    } catch (e) {
      debugPrint('[storage_tab.dart] Error: $e');
      if (!mounted) return;
      setState(() => _error = e);
    }
    await protection;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _protection.removeListener(_onControllerChanged);
    _protection.dispose();
    _runs.removeListener(_onControllerChanged);
    _runs.dispose();
    if (_ownsRestore) _restore.dispose();
    super.dispose();
  }

  Future<void> _mountDevice(StorageDevice device) async {
    setState(() => _mounting.add(device.serial));
    try {
      await StorageService.mountDevice(device.serial);
      if (!mounted) return;
      showMessage(context, '${device.name} mounted successfully');
      await refresh();
    } catch (e) {
      if (!mounted) return;
      showMessage(context, Errors.message(e, 'mount the drive'));
    } finally {
      if (mounted) setState(() => _mounting.remove(device.serial));
    }
  }

  /// Asks first, then unmounts [device] so it can be unplugged. The Quark
  /// refuses while the drive's files are in use, and that error is shown.
  Future<void> _ejectDevice(StorageDevice device) async {
    final confirmed = await QuarkWidget.showDialog<bool>(
      context,
      builder: (ctx) => EjectDriveDialog(
        driveName: device.name,
        isDefaultStorage: device.role == 'default-storage',
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _ejecting.add(device.serial));
    try {
      await StorageService.unmountDevice(device.serial);
      if (!mounted) return;
      showMessage(context, '${device.name} is safe to unplug');
      await refresh();
    } catch (e) {
      if (!mounted) return;
      showMessage(context, Errors.message(e, 'eject the drive'));
    } finally {
      if (mounted) setState(() => _ejecting.remove(device.serial));
    }
  }

  Future<void> _showRoleDialog(StorageDevice device) async {
    final health = DriveHealthController.view(device.health);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => RoleDialog(
        currentRole: device.role,
        isInternal: device.isInternal,
        health: health,
        healthId: DriveHealthController.idFor(device),
      ),
    );
    if (result == null || result == device.role || !mounted) return;

    final action = switch (result) {
      'default-storage' => DriveHealthAction.setDefaultStorage,
      'snapshot-backup' => DriveHealthAction.setBackupRole,
      _ => null,
    };
    final gate = action == null
        ? (proceed: true, acknowledgeHealth: false)
        : await _confirmHealth(device, health, action);
    if (!gate.proceed || !mounted) return;

    final creds = await _promptCredentials();
    if (creds == null || !mounted) return;

    try {
      await StorageService.setDeviceRole(
        serial: device.serial,
        role: result,
        username: creds['username']!,
        password: creds['password']!,
        acknowledgeHealth: gate.acknowledgeHealth,
      );
      if (!mounted) return;
      showMessage(context, 'Role set to ${_roleLabel(result)}');
      await refresh();
    } catch (e) {
      if (!mounted) return;
      showMessage(context, Errors.message(e, 'set the drive role'));
    }
  }

  /// Asks when [action] commits to a drive the Quark flagged. A canceled
  /// dialog does not proceed. Replace soon sends `acknowledgeHealth`. Watch
  /// never does. Assigning default storage to a drive the Quark marked worse
  /// than the current one shows the stronger warning first.
  Future<({bool proceed, bool acknowledgeHealth})> _confirmHealth(
    StorageDevice device,
    DriveHealth health,
    DriveHealthAction action,
  ) async {
    final prompt = DriveHealthController.prompt(
      verdict: health.verdict,
      action: action,
      worseThanDefault: device.health?.worseThanDefault ?? false,
    );
    if (prompt == null) return (proceed: true, acknowledgeHealth: false);

    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => DriveHealthAcknowledgment(
        id: DriveHealthController.idFor(device),
        verdict: health.verdict,
        reason: health.reason,
        strongerWarning: prompt.strongerWarning,
        requiresAcknowledgment: prompt.sendAcknowledgment,
        keepsExistingFiles: prompt.keepsExistingFiles,
        addsBackup: prompt.addsBackup,
        onConfirm: () => Navigator.pop(ctx, true),
        onCancel: () => Navigator.pop(ctx, false),
      ),
    );
    if (accepted != true) return (proceed: false, acknowledgeHealth: false);
    return (proceed: true, acknowledgeHealth: prompt.sendAcknowledgment);
  }

  Future<Map<String, String>?> _promptCredentials() =>
      QuarkWidget.showDialog<Map<String, String>>(
        context,
        builder: (ctx) => const CredentialsDialog(),
      );

  Future<void> _startBackup(StorageDevice target) async {
    final health = DriveHealthController.view(target.health);
    final gate = await _confirmHealth(
      target,
      health,
      DriveHealthAction.startBackup,
    );
    if (!gate.proceed || !mounted) return;

    // The data drives the Quark can copy: every attached drive but the
    // backup drives (#4037).
    final sources = {
      for (final d in _devices ?? const <StorageDevice>[])
        if (d.role != 'snapshot-backup' && !d.isUnmounted) d.serial: d.name,
    };
    final chosen = await QuarkWidget.showDialog<List<String>>(
      context,
      builder: (ctx) =>
          SnapshotBackupDialog(targetName: target.name, sources: sources),
    );
    if (chosen == null || !mounted) return;

    try {
      final jobId = await StorageService.startSnapshotBackup(
        targetDeviceSerial: target.serial,
        // Every drive sends none, so the Quark copies every data drive,
        // including one attached after this dialog (#3984).
        sourceSerials: chosen.length == sources.length ? null : chosen,
        acknowledgeHealth: gate.acknowledgeHealth,
      );
      if (!mounted) return;
      setState(() => _activeJobs[target.serial] = jobId);
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      showMessage(context, Errors.message(e, 'start the backup'));
    }
  }

  /// Starts a backup onto every connected backup drive, then reloads so the
  /// device list names the jobs to follow.
  Future<void> _backUpNow() async {
    final error = await _protection.backUpNow();
    if (!mounted) return;
    if (error != null) {
      showMessage(context, Errors.message(error, 'start the backup'));
    }
    StorageService.invalidateDeviceCache();
    await refresh();
  }

  /// Polls every two seconds while any backup is pending or running.
  void _startPolling() {
    _pollTimer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollStatus(),
    );
  }

  Future<void> _pollStatus() async {
    if (_activeJobs.isEmpty) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    var finished = false;
    for (final MapEntry(key: serial, value: jobId) in [
      ..._activeJobs.entries,
    ]) {
      try {
        final status = await StorageService.getSnapshotBackupStatus(jobId);
        if (!mounted) return;
        if (status.isRunning) {
          setState(() => _backupStatuses[serial] = status);
          continue;
        }
        // The result stays on the drive card through the reloaded protection
        // status, so the progress goes.
        _dropJob(serial);
        finished = true;
        if (status.isComplete) {
          showMessage(context, 'Backup completed successfully');
        } else if (status.isFailed) {
          showMessage(context, Errors.backupFailed(status.errorMsg));
        }
      } catch (e) {
        debugPrint('[storage_tab.dart] Poll error: $e');
        // The job is a row every instance of the Quark reads, so a 404 means
        // it is gone for good and another poll will not find it. Anything
        // else may be one instance's bad moment: keep polling.
        if (e is! ApiException || e.statusCode != 404 || !mounted) continue;
        _dropJob(serial);
        showMessage(context, Errors.message(e, 'check the backup'));
      }
    }
    if (_activeJobs.isEmpty) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
    if (!finished) return;
    // The cached list still names the finished job; it would be followed
    // again.
    StorageService.invalidateDeviceCache();
    await refresh();
  }

  void _dropJob(String serial) => setState(() {
    _activeJobs.remove(serial);
    _backupStatuses.remove(serial);
  });

  /// Verifies the newest backup on [device], and names the backup the Quark
  /// checked.
  Future<void> _verifyBackup(StorageDevice device) async {
    showMessage(context, 'Verifying backup integrity...');
    try {
      final result = await StorageService.verifySnapshotBackup(
        deviceSerial: device.serial,
        full: true,
      );
      if (!mounted) return;
      final run = result.run;
      final backup = run == null
          ? 'the backup'
          : 'the backup of ${backupRunLabel(run)}';
      showMessage(
        context,
        result.isHealthy
            ? 'Verified $backup: ${result.ok} files OK.'
            : 'Issues found in $backup: ${result.missing.length} missing, '
                  '${result.corrupted.length} corrupted.',
      );
    } catch (e) {
      if (!mounted) return;
      showMessage(context, Errors.message(e, 'verify the backup'));
    }
  }

  /// Restores every vault from the backup on [device] the admin picks, once
  /// they re-enter their login password. Cancel leaves the vaults alone. The
  /// snack bar is the counts and the backup, or why the Quark refused.
  Future<void> _restoreVaults(StorageDevice device) async {
    final choice =
        await QuarkWidget.showDialog<({String password, String? run})>(
          context,
          builder: (ctx) => RestoreVaultDialog(
            runs: _runs.runsFor(device.serial) ?? const [],
          ),
        );
    if (choice == null || !mounted) return;
    await _restore.restore(
      deviceSerial: device.serial,
      password: choice.password,
      run: choice.run,
    );
    if (!mounted) return;
    final error = _restore.error;
    final summary = _restore.summary;
    showMessage(
      context,
      error != null
          ? Errors.backupRun(error, 'restore the vaults')
          : summary ?? Errors.couldNot('restore the vaults'),
    );
  }

  /// Deletes the backup [run] from [device] once the admin confirms, then
  /// reloads the protection status, which no longer counts it. The controller
  /// lists the drive's backups again.
  Future<void> _deleteRun(StorageDevice device, String run) async {
    final label = backupRunLabel(run);
    final confirmed = await QuarkWidget.showDialog<bool>(
      context,
      builder: (ctx) => DeleteBackupRunDialog(runLabel: label),
    );
    if (confirmed != true || !mounted) return;
    final error = await _runs.delete(device.serial, run);
    if (!mounted) return;
    showMessage(
      context,
      error != null
          ? Errors.backupRun(error, 'delete the backup')
          : 'Deleted the backup of $label.',
    );
    if (error == null) await _protection.load();
  }

  static String _roleLabel(String role) {
    switch (role) {
      case 'default-storage':
        return 'Default Storage';
      case 'snapshot-backup':
        return 'Backup drive';
      default:
        return 'Unassigned';
    }
  }

  void _showExplainer() {
    showQuarkSheet<void>(
      context,
      title: 'Why two backup drives?',
      builder: (_) => const DataProtectionExplainerSheet(),
    );
  }

  /// The first enabled drive that is neither a backup drive nor the main
  /// storage drive. Built-in storage is the main storage drive unless a USB
  /// drive holds default storage, so it is offered only then. A USB drive
  /// with no serial is not offered: an empty serial is built-in storage. Set
  /// Role is only offered for an enabled drive.
  StorageDevice? _assignTarget() {
    final devices = _devices;
    if (devices == null) return null;
    final usbIsMain = devices.any(
      (d) => !d.isInternal && d.role == 'default-storage',
    );
    for (final device in devices) {
      if (!device.isEnabled) continue;
      if (!device.isInternal && device.serial.isEmpty) continue;
      if (device.isInternal && !usbIsMain) continue;
      if (device.role == 'snapshot-backup' ||
          device.role == 'default-storage') {
        continue;
      }
      return device;
    }
    return null;
  }

  String? _nextStepLabel() {
    switch (_protection.status?.action) {
      case DataProtectionAction.assignBackupRole:
        return 'Assign the backup role';
      // Back up now is that step, and the card always draws it.
      case DataProtectionAction.startBackup:
        return null;
      case DataProtectionAction.keepElsewhere:
        return 'Keep one backup drive somewhere else';
      case null:
        return null;
    }
  }

  /// Assign and start stay admin-only. Keeping a drive somewhere else opens
  /// the explainer, which anyone can read.
  VoidCallback? _nextStepAction(bool isAdmin) {
    switch (_protection.status?.action) {
      case DataProtectionAction.assignBackupRole:
        if (!isAdmin) return null;
        final device = _assignTarget();
        if (device == null) return null;
        return () => _showRoleDialog(device);
      case DataProtectionAction.keepElsewhere:
        return _showExplainer;
      case DataProtectionAction.startBackup:
      case null:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Every drive action is admin-only on the Quark (#1899), so anyone else
    // gets the list without them (#1928).
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.instance.isAdmin,
      builder: (context, isAdmin, _) {
        final level = _protection.level;
        final error = _protection.error;
        final showCard = _devices != null;
        return StorageDevicesBody(
          devices: _devices,
          error: _error,
          mounting: _mounting,
          protection: _protection.status,
          backupStatuses: _backupStatuses,
          isBackupRunning: _activeJobs.isNotEmpty,
          onRefresh: refresh,
          onRetry: manualRefresh,
          onManageHosts: () =>
              context.go(AppRoutes.settingsTab(SettingsTab.general)),
          onMount: isAdmin ? _mountDevice : null,
          onSetRole: isAdmin ? _showRoleDialog : null,
          onBackup: isAdmin ? _startBackup : null,
          onVerify: isAdmin ? _verifyBackup : null,
          onRestore: isAdmin ? _restoreVaults : null,
          onEject: isAdmin ? _ejectDevice : null,
          ejecting: _ejecting,
          backupRuns: isAdmin ? _runs : null,
          onDeleteRun: isAdmin ? _deleteRun : null,
          header: showCard
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Where the drives sit beside people, clients and
                    // folder access (#2484).
                    if (isAdmin) ...[
                      const AdminMapCard(here: AdminMapStop.disks),
                      const SizedBox(height: 16),
                    ],
                    DataProtectionStatusCard(
                      level: level,
                      sentence: _protection.status?.sentence,
                      nextStepLabel: _nextStepLabel(),
                      onNextStep: _nextStepAction(isAdmin),
                      onBackUpNow:
                          isAdmin && _protection.backUpNowTargets.isNotEmpty
                          ? _backUpNow
                          : null,
                      onExplain: _showExplainer,
                      isLoading: _protection.isLoading,
                      error: error == null
                          ? null
                          : Errors.message(error, 'check the backup'),
                    ),
                  ],
                )
              : null,
        );
      },
    );
  }
}
