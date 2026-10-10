import 'package:flutter/material.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The drives a vault backup can be restored from, as a radio list (#1665).
///
/// Data in, callbacks out: it renders loading, a failed listing, no drives,
/// or the list, and never fetches. Keys: `vault_restore_device_<serial>` on
/// each drive, `vault_restore_devices_retry` on the button that lists the
/// drives again.
///
/// ```dart
/// VaultRestoreDevicePicker(
///   devices: controller.devices,
///   selectedSerial: controller.selectedSerial,
///   isLoading: controller.isLoading,
///   error: controller.loadError,
///   onSelect: controller.selectDevice,
///   onRetry: controller.load,
/// )
/// ```
class VaultRestoreDevicePicker extends StatelessWidget {
  /// The drives to offer.
  final List<StorageDevice> devices;

  /// The serial of the picked drive, or null when none is.
  final String? selectedSerial;

  /// Whether the drives are being fetched.
  final bool isLoading;

  /// User-facing copy for a failed listing, or null.
  final String? error;

  /// Called with a drive's serial when it is picked.
  final ValueChanged<String> onSelect;

  /// Called to list the drives again.
  final VoidCallback onRetry;

  const VaultRestoreDevicePicker({
    super.key,
    required this.devices,
    required this.selectedSerial,
    required this.isLoading,
    required this.error,
    required this.onSelect,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: QuarkLoader(size: 20)),
      );
    }
    final error = this.error;
    if (error != null || devices.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            error ??
                'No backup drive found. Plug one in and turn it on under '
                    'System › Storage, then check again.',
            style: error == null
                ? null
                : TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton.icon(
            key: const ValueKey('vault_restore_devices_retry'),
            onPressed: onRetry,
            icon: const Icon(QuarkIcons.refresh),
            label: const Text('Check again'),
          ),
        ],
      );
    }
    return RadioGroup<String>(
      groupValue: selectedSerial,
      onChanged: (serial) {
        if (serial != null) onSelect(serial);
      },
      child: Column(
        children: [
          for (final device in devices)
            RadioListTile<String>(
              key: ValueKey('vault_restore_device_${device.serial}'),
              contentPadding: EdgeInsets.zero,
              value: device.serial,
              title: Text(
                device.name.isNotEmpty
                    ? device.name
                    : device.model.isNotEmpty
                    ? device.model
                    : 'USB drive',
              ),
              subtitle: Text(device.usedDisplay),
            ),
        ],
      ),
    );
  }
}
