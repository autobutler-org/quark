import 'package:flutter/material.dart';
import 'package:quark/widgets/settings/hostname_section.dart';
import 'package:quark/widgets/settings/ssh_access_section.dart';

/// The Network tab of Settings (#2350): remote access, the connected
/// devices, and, for an admin, the device name (#2344) and SSH access.
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
    this.thisPhone,
    this.showDesktopNote = false,
    this.header,
    super.key,
  });

  /// Whether a Quark address is set. Without one there is nothing to read.
  final bool hasHost;

  /// Whether the Quark says this user is an admin; the device name (#2344)
  /// and SSH access (#2131) are theirs only.
  final bool isAdmin;

  /// The remote access card, shown while a Quark is set.
  final Widget remoteAccess;

  /// The connected devices card, shown while a Quark is set.
  final Widget connectedDevices;

  /// This phone's own remote access switch. Null leaves the section out,
  /// as on web and desktop, where this device does not run a node.
  final Widget? thisPhone;

  /// Whether to say, under the remote access card, that the desktop app
  /// cannot use remote access yet (#3779).
  final bool showDesktopNote;

  /// What [showDesktopNote] says. Reword it when desktop remote access ships
  /// (#2877).
  static const desktopRemoteAccessNote =
      "Remote access isn't available in the desktop app yet. At home, Quark "
      'works as usual.';

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
          if (showDesktopNote) ...[
            const SizedBox(height: 8),
            const Text(desktopRemoteAccessNote),
          ],
          const SizedBox(height: 24),
          if (thisPhone != null) ...[
            const Text('This phone', style: heading),
            const SizedBox(height: 8),
            thisPhone!,
            const SizedBox(height: 24),
          ],
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
        // Admin-only: what the device is called on the network (#2344), and
        // a shell login on it (#2131).
        if (hasHost && isAdmin) ...[
          const SizedBox(height: 24),
          // Brings its own heading and the gap under it, and takes no space
          // on a Quark that can't be renamed.
          const HostnameSection(),
          const Text('SSH access', style: heading),
          const SizedBox(height: 8),
          const SshAccessSection(),
        ],
      ],
    );
  }
}
