import 'package:flutter/material.dart';
import 'package:quark/widgets/settings/repair_installation_section.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Updates tab of Settings (#2350): the Quark's installed version, and,
/// for an admin, updating it, automatic updates and repairing the
/// installation.
///
/// Called Updates rather than System, which names the Health, Storage and
/// Jobs page (#2351). The page owns the values; this tab renders them and
/// reports what the user picked.
class SettingsUpdatesTab extends StatelessWidget {
  /// Creates the tab.
  const SettingsUpdatesTab({
    required this.hasHost,
    required this.isAdmin,
    required this.disconnected,
    required this.installedVersion,
    required this.installedReleaseUrl,
    required this.availableVersions,
    required this.selectedVersion,
    required this.isLoadingVersion,
    required this.isUpdating,
    required this.versionError,
    required this.onSelectVersion,
    required this.onUpdate,
    required this.onOpenReleaseNotes,
    required this.autoUpdate,
    required this.isLoadingAutoUpdate,
    required this.autoUpdateError,
    required this.onAutoUpdateChanged,
    this.header,
    super.key,
  });

  /// Whether a Quark address is set. Without one there is nothing to read.
  final bool hasHost;

  /// Whether the Quark says this user is an admin.
  final bool isAdmin;

  /// Whether the Quark is unreachable, which the page banner explains.
  final bool disconnected;

  /// How the Quark's version reads, or null before it is read.
  final String? installedVersion;

  /// Where the installed version's release notes live, or null.
  final String? installedReleaseUrl;

  /// The versions the Quark can update to, newest first.
  final List<String> availableVersions;

  /// The version picked to update to.
  final String? selectedVersion;

  /// Whether the version is being read.
  final bool isLoadingVersion;

  /// Whether an update is being started.
  final bool isUpdating;

  /// Why the version could not be read, or null.
  final String? versionError;

  /// Called with the version the user picked.
  final ValueChanged<String?> onSelectVersion;

  /// Starts the update to [selectedVersion].
  final VoidCallback onUpdate;

  /// Opens release notes at the given URL.
  final ValueChanged<String> onOpenReleaseNotes;

  /// Whether the Quark updates itself daily.
  final bool autoUpdate;

  /// Whether that setting is being read.
  final bool isLoadingAutoUpdate;

  /// Why that setting could not be read, or null.
  final String? autoUpdateError;

  /// Called when the user flips automatic updates.
  final ValueChanged<bool> onAutoUpdateChanged;

  /// Shown above the tab's content and scrolled with it, such as the
  /// page's disconnected banner; null shows nothing.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    const autoUpdateHint = Text(
      'Quark will check for and install updates daily',
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (header != null) ...[header!, const SizedBox(height: 24)],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Names whose version this is. "Installed version" alone sat
                // opposite the app's own line and left the reader to work out
                // which was which (#2035).
                const Text(
                  'Quark version (installed)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                if (!hasHost)
                  const Text(
                    'Not connected — add your Quark address under Backend '
                    'hosts, on the General tab',
                  )
                else if (isLoadingVersion)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (versionError != null)
                  Text(
                    disconnected ? quarkDisconnectedShort : versionError!,
                    style: TextStyle(color: error),
                  )
                else
                  Text(
                    installedVersion ?? 'Unknown',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (installedReleaseUrl != null && !isLoadingVersion)
                  TextButton.icon(
                    onPressed: () => onOpenReleaseNotes(installedReleaseUrl!),
                    icon: const Icon(QuarkIcons.open_in_new, size: 16),
                    label: const Text("What's in this release"),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                const SizedBox(height: 16),
                if (availableVersions.isEmpty &&
                    !isLoadingVersion &&
                    versionError == null &&
                    hasHost)
                  const Text('No updates available')
                else if (availableVersions.isNotEmpty && isAdmin) ...[
                  DropdownButtonFormField<String>(
                    initialValue: selectedVersion,
                    items: [
                      for (final v in availableVersions)
                        DropdownMenuItem<String>(value: v, child: Text(v)),
                    ],
                    onChanged: (isLoadingVersion || isUpdating)
                        ? null
                        : onSelectVersion,
                    decoration: const InputDecoration(
                      labelText: 'Update Quark to version',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: (selectedVersion == null || isUpdating)
                          ? null
                          : onUpdate,
                      icon: isUpdating
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(QuarkIcons.update),
                      label: Text(isUpdating ? 'Updating...' : 'Start update'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (hasHost && isAdmin) ...[
          const SizedBox(height: 16),
          Card(
            child: isLoadingAutoUpdate
                ? const ListTile(
                    title: Text('Automatic updates'),
                    subtitle: autoUpdateHint,
                    trailing: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : SwitchListTile(
                    title: const Text('Automatic updates'),
                    subtitle: autoUpdateError != null
                        ? Text(
                            disconnected
                                ? quarkDisconnectedShort
                                : autoUpdateError!,
                            style: TextStyle(color: error),
                          )
                        : autoUpdateHint,
                    value: autoUpdate,
                    onChanged: autoUpdateError != null
                        ? null
                        : onAutoUpdateChanged,
                  ),
          ),
          const SizedBox(height: 24),
          // Renders nothing unless this Quark can repair itself (#2121).
          const RepairInstallationSection(),
        ],
      ],
    );
  }
}
