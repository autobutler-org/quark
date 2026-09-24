import 'package:flutter/material.dart';
import 'package:quark/widgets/settings/ssh_access_section.dart';

/// The Network tab of Settings (#2350): remote access, the connected
/// devices, and, for an admin, SSH access.
///
/// The page loads the data and builds [remoteAccess] and [connectedDevices];
/// this tab lays them out and says what is missing while no Quark is set.
class SettingsNetworkTab extends StatelessWidget {
  /// Creates the tab.
  const SettingsNetworkTab({
    required this.hasHost,
    required this.isAdmin,
    required this.remoteAccess,
    required this.connectedDevices,
    this.header,
    super.key,
  });

  /// Whether a Quark address is set. Without one there is nothing to read.
  final bool hasHost;

  /// Whether the Quark says this user is an admin; SSH access is theirs
  /// only (#2131).
  final bool isAdmin;

  /// The remote access card, shown while a Quark is set.
  final Widget remoteAccess;

  /// The connected devices card, shown while a Quark is set.
  final Widget connectedDevices;

  /// Shown above the tab's content and scrolled with it, such as the
  /// page's disconnected banner; null shows nothing.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    const heading = TextStyle(fontSize: 16, fontWeight: FontWeight.bold);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (header != null) ...[header!, const SizedBox(height: 24)],
        if (hasHost) ...[
          const Text('Remote access', style: heading),
          const SizedBox(height: 8),
          remoteAccess,
          const SizedBox(height: 24),
        ],
        const Text('Connected devices', style: heading),
        const SizedBox(height: 8),
        if (hasHost)
          connectedDevices
        else
          const Text(
            'Not connected — add your Quark address under Backend hosts, '
            'on the General tab',
          ),
        // Admin-only: a shell login on the device (#2131).
        if (hasHost && isAdmin) ...[
          const SizedBox(height: 24),
          const Text('SSH access', style: heading),
          const SizedBox(height: 8),
          const SshAccessSection(),
        ],
      ],
    );
  }
}
