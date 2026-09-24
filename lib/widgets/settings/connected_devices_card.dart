import 'package:flutter/material.dart';
import 'package:quark/services/connected_devices_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Connected devices card on the Network tab of Settings: the clients
/// that have talked to this Quark, and, for an admin, a way to remove one.
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

  /// Called with the id of the device record to remove.
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
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
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
                leading: const Icon(QuarkIcons.devices),
                title: Text(device.ipAddress),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (device.userAgent.isNotEmpty)
                      Text(
                        device.userAgent,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    Text(
                      '${device.requestCount} request${device.requestCount == 1 ? '' : 's'} · last seen ${_formatRelative(device.lastSeenAt)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                isThreeLine: device.userAgent.isNotEmpty,
                trailing: isAdmin
                    ? IconButton(
                        icon: const Icon(QuarkIcons.delete_outline),
                        tooltip: 'Remove',
                        onPressed: () => onRemove(device.id),
                      )
                    : null,
              ),
        ],
      ),
    );
  }
}

/// How long ago [dt] was, in the shortest unit that reads naturally.
String _formatRelative(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
