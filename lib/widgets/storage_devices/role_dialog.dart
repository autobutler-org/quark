import 'package:material_ui/material_ui.dart';
import 'package:quark/widgets/storage_devices/drive_health_section.dart';
import 'package:quark/widgets/storage_devices/role_option.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Asks which role a device should take on. Pops with the chosen role string.
///
/// Default storage is where the upload and new folder pickers start (#3194),
/// and on a USB drive it is also what live sync copies built-in storage onto.
/// [health] is the drive's verdict, shown above the choices.
class RoleDialog extends StatelessWidget {
  const RoleDialog({
    required this.currentRole,
    this.isInternal = false,
    this.health = const DriveHealth(verdict: DriveHealthVerdict.unknown),
    this.healthId = 'drive',
    super.key,
  });

  final String currentRole;

  /// Whether the device is built-in storage. It can be a backup drive too:
  /// other drives are copied onto it, and it is not copied onto itself.
  final bool isInternal;

  /// The drive's health. Omitted callers see Unknown, never Healthy.
  final DriveHealth health;

  /// Key id for [health], so the badge does not collide with the card behind.
  final String healthId;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Set Device Role'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: DriveHealthSection(health: health, id: healthId),
        ),
        RoleOption(
          title: 'Default Storage',
          subtitle: isInternal
              ? 'Uploads and new folders start here'
              : 'Uploads and new folders start here. Built-in storage is '
                    'also copied onto it.',
          selected: currentRole == 'default-storage',
          onTap: () => Navigator.pop(context, 'default-storage'),
        ),
        RoleOption(
          title: 'Backup drive',
          subtitle: isInternal
              ? 'Other drives are backed up onto it'
              : 'Your other drives are copied onto it when you back up. Keep it '
                    'somewhere safe between backups.',
          selected: currentRole == 'snapshot-backup',
          onTap: () => Navigator.pop(context, 'snapshot-backup'),
        ),
        RoleOption(
          title: 'Unassigned',
          subtitle: 'No special role',
          selected: currentRole == 'unassigned',
          onTap: () => Navigator.pop(context, 'unassigned'),
        ),
      ],
    );
  }
}
