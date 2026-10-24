import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/data_protection_controller.dart';
import 'package:quark/controllers/drive_health_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/data_protection_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/widgets/storage_devices/credentials_dialog.dart';
import 'package:quark/widgets/storage_devices/role_dialog.dart';
import 'package:quark/widgets/storage_devices/snapshot_backup_dialog.dart';
import 'package:quark/widgets/storage_devices/storage_devices_body.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The System page's Storage tab: how protected the files are, the drives the
/// Quark can see, their status and role, and the actions to mount, rename or
/// back them up.
class StorageTab extends StatefulWidget {
  const StorageTab({this.onRefreshingChanged, super.key});

  /// Called with whether a refresh is in flight whenever that changes, so
  /// the page's app bar can show it.
  final ValueChanged<bool>? onRefreshingChanged;

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
  String? _activeBackupJobId;
  BackupJobStatus? _backupStatus;
  Timer? _pollTimer;
  late final DataProtectionController _protection;

  @override
  void initState() {
    _protection = DataProtectionController();
    _protection.addListener(_onProtection);
    super.initState();
  }

  void _onProtection() {
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
      });
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
    _protection.removeListener(_onProtection);
    _protection.dispose();
    super.dispose();
  }

  Future<void> _mountDevice(StorageDevice device) async {
    setState(() => _mounting.add(device.serial));
    try {
      await StorageService.mountDevice(device.serial);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${device.name} mounted successfully')),
      );
      await refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'mount the drive'))),
      );
    } finally {
      if (mounted) setState(() => _mounting.remove(device.serial));
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Role set to ${_roleLabel(result)}')),
      );
      await refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'set the drive role'))),
      );
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

    final confirmed = await QuarkWidget.showDialog<bool>(
      context,
      builder: (ctx) => SnapshotBackupDialog(targetName: target.name),
    );
    if (confirmed != true || !mounted) return;

    try {
      final jobId = await StorageService.startSnapshotBackup(
        targetDeviceSerial: target.serial,
        acknowledgeHealth: gate.acknowledgeHealth,
      );
      if (!mounted) return;
      setState(() => _activeBackupJobId = jobId);
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'start the backup'))),
      );
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollStatus(),
    );
  }

  Future<void> _pollStatus() async {
    final jobId = _activeBackupJobId;
    if (jobId == null) return;
    try {
      final status = await StorageService.getSnapshotBackupStatus(jobId);
      if (!mounted) return;
      setState(() => _backupStatus = status);
      if (!status.isRunning) {
        _pollTimer?.cancel();
        _pollTimer = null;
        if (status.isComplete) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup completed successfully')),
          );
        } else if (status.isFailed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Backup failed: ${status.errorMsg ?? "unknown error"}',
              ),
            ),
          );
        }
        await refresh();
      }
    } catch (e) {
      debugPrint('[storage_tab.dart] Poll error: $e');
      // The job is a row every instance of the Quark reads, so a 404 means
      // it is gone for good and another poll will not find it. Anything else
      // may be one instance's bad moment: keep polling.
      if (e is! ApiException || e.statusCode != 404 || !mounted) return;
      _pollTimer?.cancel();
      _pollTimer = null;
      setState(() {
        _activeBackupJobId = null;
        _backupStatus = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'check the backup'))),
      );
    }
  }

  Future<void> _verifyBackup(StorageDevice device) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Verifying backup integrity...')),
    );
    try {
      final result = await StorageService.verifySnapshotBackup(
        deviceSerial: device.serial,
        full: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isHealthy
                ? 'Backup verified: ${result.ok} files OK'
                : 'Issues found: ${result.missing.length} missing, ${result.corrupted.length} corrupted',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'verify the backup'))),
      );
    }
  }

  static String _roleLabel(String role) {
    switch (role) {
      case 'default-storage':
        return 'Default Storage';
      case 'snapshot-backup':
        return 'Snapshot Backup';
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

  /// The first enabled external drive that is not already a backup drive.
  /// Set Role is only offered for an enabled drive.
  StorageDevice? _assignTarget() {
    final devices = _devices;
    if (devices == null) return null;
    for (final device in devices) {
      if (!device.isEnabled || device.isInternal || device.serial.isEmpty) {
        continue;
      }
      if (device.role == 'snapshot-backup') continue;
      return device;
    }
    return null;
  }

  /// The drive the Quark named for a start-backup step.
  StorageDevice? _backupTarget() {
    final serial = _protection.status?.backupTargetSerial;
    final devices = _devices;
    if (serial == null || devices == null) return null;
    for (final device in devices) {
      if (device.serial == serial) return device;
    }
    return null;
  }

  String? _nextStepLabel() {
    switch (_protection.status?.action) {
      case DataProtectionAction.assignBackupRole:
        return 'Assign the backup role';
      case DataProtectionAction.startBackup:
        return 'Start a backup';
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
      case DataProtectionAction.startBackup:
        if (!isAdmin) return null;
        final device = _backupTarget();
        if (device == null) return null;
        return () => _startBackup(device);
      case DataProtectionAction.keepElsewhere:
        return _showExplainer;
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
          backupStatus: _backupStatus,
          activeBackupJobId: _activeBackupJobId,
          onRefresh: refresh,
          onRetry: manualRefresh,
          onManageHosts: () =>
              context.go(AppRoutes.settingsTab(SettingsTab.general)),
          onMount: isAdmin ? _mountDevice : null,
          onSetRole: isAdmin ? _showRoleDialog : null,
          onBackup: isAdmin ? _startBackup : null,
          onVerify: isAdmin ? _verifyBackup : null,
          header: showCard
              ? DataProtectionStatusCard(
                  level: level,
                  sentence: _protection.status?.sentence,
                  drives: _protection.drives,
                  nextStepLabel: _nextStepLabel(),
                  onNextStep: _nextStepAction(isAdmin),
                  onExplain: _showExplainer,
                  isLoading: _protection.isLoading,
                  error: error == null
                      ? null
                      : Errors.message(error, 'check the backup'),
                )
              : null,
          protectionBadge: level == null
              ? null
              : QuarkTintBadge(
                  key: const ValueKey('data_protection_badge'),
                  label: level.label,
                  color: dataProtectionLevelColor(
                    QuarkTokens.of(context),
                    level,
                  ),
                  semanticLabel: '${level.label} protection',
                ),
        );
      },
    );
  }
}
