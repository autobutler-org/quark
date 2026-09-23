import 'package:flutter/material.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One toggle per attached device, shown on wide viewports only — the compact
/// layout folds the same filter into the Views menu.
///
/// Probe keys: `file_top_bar_device_<devicePath>`, one per device.
class FileTopBarDeviceChips extends StatelessWidget {
  const FileTopBarDeviceChips({
    required this.devices,
    required this.activeDevicePaths,
    required this.onDeviceToggled,
    super.key,
  });

  final List<StorageDevice> devices;
  final Set<String>? activeDevicePaths;
  final ValueChanged<String>? onDeviceToggled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: QuarkTokens.of(context).spacingXs,
      children: devices.map((device) {
        final isSelected =
            activeDevicePaths?.contains(device.devicePath) ?? true;
        return QuarkBarChip(
          key: ValueKey('file_top_bar_device_${device.devicePath}'),
          icon: isSelected
              ? QuarkIcons.check_circle_outline_rounded
              : QuarkIcons.circle_outlined,
          label: device.name.isNotEmpty ? device.name : device.mountPoint,
          onPressed: onDeviceToggled != null
              ? () => onDeviceToggled!(device.devicePath)
              : null,
          active: isSelected,
        );
      }).toList(),
    );
  }
}
