import 'package:flutter/material.dart';
import 'package:quark/services/connected_devices_service.dart';
import 'package:quark/utils/device_label.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/relative_time.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Connected devices card on the Network tab of Settings: the clients
/// that have talked to this Quark, and, for an admin, a way to remove one.
///
/// A row names its client with [deviceLabel], never by IP address or
/// User-Agent, and the row of the client showing the list reads "This
/// browser" (#2051). Removing a row asks first.
///
/// Keys: `connected_device_tile_<id>`, `connected_device_remove_<id>`.
class ConnectedDevicesCard extends StatelessWidget {
  /// Creates the card.
  const ConnectedDevicesCard({
    required this.devices,
    required this.isLoading,
    required this.error,
    required this.disconnected,
    required this.isAdmin,
    required this.onRefresh,
    required this.onRemove,
    super.key,
  });

  /// The devices the Quark has recorded.
  final List<ConnectedDevice> devices;

  /// Whether the list is being read.
  final bool isLoading;

  /// Why the list could not be read, or null.
  final String? error;

  /// Whether the Quark is unreachable, which the page banner explains.
  final bool disconnected;

  /// Whether the user may remove a device record (#1899).
  final bool isAdmin;

  /// Reads the list again.
  final VoidCallback onRefresh;

  /// Called with the id of the device record to remove, once the user has
  /// confirmed.
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: const Text(
          'Client connections',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          isLoading
              ? 'Loading...'
              : error != null
              ? Errors.loadFailedShort
              : devices.isEmpty
              ? 'No devices recorded yet'
              : '${devices.length} device${devices.length == 1 ? '' : 's'}',
        ),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: RefreshIconButton(
                isRefreshing: isLoading,
                onPressed: onRefresh,
                tooltip: 'Refresh devices',
              ),
            ),
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Center(child: QuarkLoader(size: 20)),
            )
          else if (error != null)
            ListTile(
              leading: Icon(
                QuarkIcons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(disconnected ? quarkDisconnectedShort : error!),
            )
          else if (devices.isEmpty)
            const ListTile(title: Text('No devices recorded yet'))
          else
            for (final device in devices)
              ListTile(
                key: ValueKey('connected_device_tile_${device.id}'),
                leading: const Icon(QuarkIcons.devices),
                title: Text(
                  device.current
                      ? currentDeviceLabel(device.userAgent)
                      : deviceLabel(device.userAgent),
                ),
                subtitle: Text(
                  device.current
                      ? '${deviceLabel(device.userAgent)} · last active '
                            '${formatRelative(device.lastSeenAt)}'
                      : 'Last active ${formatRelative(device.lastSeenAt)}',
                ),
                // Not on the user's own row: the request that removes it
                // records the caller again.
                trailing: isAdmin && !device.current
                    ? IconButton(
                        key: ValueKey('connected_device_remove_${device.id}'),
                        icon: const Icon(QuarkIcons.delete_outline),
                        tooltip: 'Remove from this list',
                        onPressed: () async {
                          final confirmed = await confirmAction(
                            context,
                            title: 'Remove ${deviceLabel(device.userAgent)}?',
                            message:
                                'It leaves this list, and comes back the next '
                                'time it talks to your Quark. To sign a '
                                'device out, use Sessions on the Account tab.',
                            confirmLabel: 'Remove',
                          );
                          if (confirmed == true) onRemove(device.id);
                        },
                      )
                    : null,
              ),
        ],
      ),
    );
  }
}
