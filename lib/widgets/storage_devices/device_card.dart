import 'package:flutter/material.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/storage_devices/role_badge.dart';
import 'package:quark/widgets/storage_devices/vault_badge.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One storage device: identity, usage bar, category chips, and the actions
/// that apply to it. A null callback hides its button.
class DeviceCard extends StatelessWidget {
  const DeviceCard({
    required this.device,
    required this.isMounting,
    this.isVaultDevice = false,
    this.onMount,
    this.onSetRole,
    this.onBackup,
    this.onVerify,
    this.isBackupRunning = false,
    super.key,
  });

  final StorageDevice device;
  final bool isMounting;
  final bool isVaultDevice;
  final VoidCallback? onMount;
  final VoidCallback? onSetRole;
  final VoidCallback? onBackup;
  final VoidCallback? onVerify;
  final bool isBackupRunning;

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
                      ? QuarkIcons.computer_outlined
                      : QuarkIcons.usb_outlined,
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
                if (isVaultDevice) const VaultBadge(),
                if (device.role != 'unassigned') RoleBadge(role: device.role),
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
              QuarkStorageBar(usedFraction: usedPct),
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
                    ? const QuarkLoader(size: 14)
                    : const Icon(QuarkIcons.link_outlined, size: 16),
                label: Text(isMounting ? 'Mounting…' : 'Mount'),
              ),
            ],

            // Role + backup actions for enabled external devices
            if (device.isEnabled && !device.isInternal) ...[
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
                      label: const Text('Back Up'),
                    ),
                  if (onVerify != null)
                    OutlinedButton.icon(
                      onPressed: isBackupRunning ? null : onVerify,
                      icon: const Icon(QuarkIcons.verified_outlined, size: 16),
                      label: const Text('Verify'),
                    ),
                ],
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
