import 'package:autobutler/router.dart';
import 'package:autobutler/services/app_settings.dart';
import 'package:autobutler/services/storage_service.dart';
import 'package:autobutler/utils/auto_refresh_mixin.dart';
import 'package:autobutler/widgets/autobutler_drawer.dart';
import 'package:autobutler/widgets/core/autobutler_storage_bar.dart';
import 'package:autobutler/widgets/layout/autobutler_app_bar.dart';
import 'package:autobutler/widgets/refresh_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class StorageDevicesPage extends StatefulWidget {
  const StorageDevicesPage({super.key});

  @override
  State<StorageDevicesPage> createState() => _StorageDevicesPageState();
}

class _StorageDevicesPageState extends State<StorageDevicesPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  List<StorageDevice>? _devices;
  String? _error;
  final Set<String> _mounting = {};

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
      final devices = await StorageService.listDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _error = null;
      });
    } catch (e) {
      debugPrint('[storage_devices_page.dart] Error: $e');
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Mount failed: $e')));
    } finally {
      if (mounted) setState(() => _mounting.remove(device.serial));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AutobutlerAppBar(
        label: 'Devices',
        icon: Icons.device_hub_outlined,
        actions: [
          RefreshIconButton(
            isRefreshing: isRefreshing,
            onPressed: manualRefresh,
          ),
        ],
      ),
      drawer: AutobutlerDrawer(
        activeSection: AutobutlerDrawerSection.devices,
        onTapCirrus: () => context.go(AppRoutes.cirrus),
        onTapPhotos: () => context.go(AppRoutes.photos),
        onTapDevices: () => Navigator.of(context).pop(),
        onTapHealth: () => context.go(AppRoutes.health),
        onTapSettings: () => context.go(AppRoutes.settings),
        onTapPlugins: () => context.go(AppRoutes.plugins),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (AppSettings.instance.activeHost == null) {
      return const Center(child: Text('No butler host configured.'));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Error: $_error',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }
    if (_devices == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_devices!.isEmpty) {
      return const Center(child: Text('No storage devices detected.'));
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _devices!.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _DeviceCard(
          device: _devices![i],
          isMounting: _mounting.contains(_devices![i].serial),
          onMount: _devices![i].serial.isNotEmpty
              ? () => _mountDevice(_devices![i])
              : null,
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.isMounting,
    this.onMount,
  });

  final StorageDevice device;
  final bool isMounting;
  final VoidCallback? onMount;

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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: name + status badge
            Row(
              children: [
                Icon(
                  device.isInternal
                      ? Icons.computer_outlined
                      : Icons.usb_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    device.name.isNotEmpty ? device.name : device.mountPoint,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (device.isEnabled)
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
            const SizedBox(height: 6),

            // Mount point + filesystem
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

            // Storage bar (only when totalBytes is known)
            if (device.totalBytes > 0) ...[
              const SizedBox(height: 12),
              AutobutlerStorageBar(usedFraction: usedPct),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
            ],

            // Category chips
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
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],

            // Mount button for unmounted USB devices
            if (!device.isEnabled && onMount != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: isMounting ? null : onMount,
                icon: isMounting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_outlined, size: 16),
                label: Text(isMounting ? 'Mounting…' : 'Mount'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
