import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/services/vault_service.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/storage_devices/role_dialog.dart';
import 'package:quark/widgets/storage_devices/storage_devices_body.dart';

class StorageDevicesPage extends StatefulWidget {
  const StorageDevicesPage({super.key});

  @override
  State<StorageDevicesPage> createState() => _StorageDevicesPageState();
}

class _StorageDevicesPageState extends State<StorageDevicesPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  List<StorageDevice>? _devices;

  /// The thrown object, not its message — the render decides whether it means
  /// "your Quark is unreachable" or "the request failed" (#1637).
  Object? _error;
  final Set<String> _mounting = {};
  String? _activeBackupJobId;
  BackupJobStatus? _backupStatus;
  Timer? _pollTimer;
  String _vaultDeviceSerial = '';

  @override
  Future<void> refresh() async {
    if (AppSettings.instance.activeHost == null) {
      setState(() {
        _devices = null;
        _error = null;
      });
      return;
    }
    try {
      final results = await Future.wait([
        StorageService.listDevices(),
        VaultService.getStorageLocation()
            .then((loc) => loc.deviceSerial)
            .catchError((_) => ''),
      ]);
      if (!mounted) return;
      setState(() {
        _devices = results[0] as List<StorageDevice>;
        _vaultDeviceSerial = results[1] as String;
        _error = null;
      });
    } catch (e) {
      debugPrint('[storage_devices_page.dart] Error: $e');
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
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
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => RoleDialog(currentRole: device.role),
    );
    if (result == null || result == device.role || !mounted) return;

    final creds = await _promptCredentials();
    if (creds == null || !mounted) return;

    try {
      await StorageService.setDeviceRole(
        serial: device.serial,
        role: result,
        username: creds['username']!,
        password: creds['password']!,
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

  Future<Map<String, String>?> _promptCredentials() async {
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final result = await QuarkWidget.showDialog<Map<String, String>>(
      context,
      builder: (ctx) => QuarkWidget.alertDialog(
        title: const Text('Authenticate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter your credentials to continue.'),
            const SizedBox(height: 12),
            TextField(
              controller: usernameCtrl,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, {
              'username': usernameCtrl.text,
              'password': passwordCtrl.text,
            }),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    usernameCtrl.dispose();
    passwordCtrl.dispose();
    return result;
  }

  Future<void> _startBackup(StorageDevice target) async {
    final creds = await _promptCredentials();
    if (creds == null || !mounted) return;

    final recoveryCtrl = TextEditingController();
    final includeVault = await QuarkWidget.showDialog<bool>(
      context,
      builder: (ctx) => QuarkWidget.alertDialog(
        title: const Text('Snapshot Backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Back up all devices to ${target.name.isNotEmpty ? target.name : "this drive"}.',
            ),
            const SizedBox(height: 16),
            const Text(
              'Optionally include your vault with a recovery password:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: recoveryCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Recovery password (optional)',
                helperText: 'Min 8 characters. Separate from master password.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Start Backup'),
          ),
        ],
      ),
    );
    if (includeVault != true || !mounted) {
      recoveryCtrl.dispose();
      return;
    }

    try {
      final jobId = await StorageService.startSnapshotBackup(
        targetDeviceSerial: target.serial,
        username: creds['username'],
        password: creds['password'],
        recoveryPassword: recoveryCtrl.text.isNotEmpty
            ? recoveryCtrl.text
            : null,
      );
      recoveryCtrl.dispose();
      if (!mounted) return;
      setState(() => _activeBackupJobId = jobId);
      _startPolling();
    } catch (e) {
      recoveryCtrl.dispose();
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
      debugPrint('[storage_devices_page.dart] Poll error: $e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: QuarkAppBar(
        label: 'Devices',
        icon: QuarkIcons.device_hub_outlined,
        actions: [
          RefreshIconButton(
            isRefreshing: isRefreshing,
            onPressed: manualRefresh,
          ),
          const AppThemeToggle(),
        ],
      ),
      drawer: QuarkDrawer(
        activeSection: QuarkDrawerSection.devices,
        onTapFiles: () => context.go(AppRoutes.files),
        onTapPhotos: () => context.go(AppRoutes.photos),
        onTapTrash: () => context.go(AppRoutes.trash),
        onTapDocs: () => context.go(AppRoutes.docs),
        onTapSheets: () => context.go(AppRoutes.sheets),
        onTapDevices: () => Navigator.of(context).pop(),
        onTapHealth: () => context.go(AppRoutes.health),
        onTapVault: () => context.go(AppRoutes.vault),
        onTapSettings: () => context.go(AppRoutes.settings),
      ),
      body: StorageDevicesBody(
        devices: _devices,
        error: _error,
        mounting: _mounting,
        vaultDeviceSerial: _vaultDeviceSerial,
        backupStatus: _backupStatus,
        activeBackupJobId: _activeBackupJobId,
        onRefresh: refresh,
        onRetry: manualRefresh,
        onManageHosts: () => context.go(AppRoutes.settings),
        onMount: _mountDevice,
        onSetRole: _showRoleDialog,
        onBackup: _startBackup,
        onVerify: _verifyBackup,
      ),
    );
  }
}
