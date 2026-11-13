import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark_icons/quark_icons.dart';

/// One of the things an admin looks after, each kept on its own page.
enum AdminMapStop { people, access, clients, disks, passwords }

/// A collapsed "Where things live" legend for an admin (#2484): people,
/// who can open which folders, connected clients, disks, and passwords, each
/// with a sentence on how it relates to the others and a link to the page
/// that manages it. The Users page, Settings' Network tab and System's
/// Storage tab each show it with [here] set to their own stop, which reads
/// "You are here" and does not link.
///
/// Keys: `admin_map` on the tile, `admin_map_<stop>` on each row.
class AdminMapCard extends StatelessWidget {
  /// Creates the card.
  const AdminMapCard({required this.here, super.key});

  /// The stop the page showing this card manages.
  final AdminMapStop here;

  static final _stops = [
    (
      stop: AdminMapStop.people,
      icon: QuarkIcons.person_outline,
      title: 'People',
      what:
          'Accounts sign in, and groups gather them so a folder can be '
          'shared with several at once.',
      where: 'Users',
      route: AppRoutes.users,
    ),
    (
      stop: AdminMapStop.access,
      icon: QuarkIcons.share_outlined,
      title: 'Who can access what',
      what:
          'Each person has a home folder and each group a folder of its '
          'own. Share… on any folder in Files lets a person or a group open '
          'it. An admin can reach everything.',
      where: 'Files',
      route: AppRoutes.files,
    ),
    (
      stop: AdminMapStop.clients,
      icon: QuarkIcons.devices,
      title: 'Connected clients',
      what:
          'The browsers and apps people have used to talk to this Quark. '
          'Signing one out is under Sessions on the Account tab.',
      where: 'Settings › Network',
      route: AppRoutes.settingsTab(SettingsTab.network),
    ),
    (
      stop: AdminMapStop.disks,
      icon: QuarkIcons.storage,
      title: 'Disks',
      what:
          'The drives that hold everyone’s files, and which ones keep the '
          'backups.',
      where: 'System › Storage',
      route: AppRoutes.systemTab(SystemTab.storage),
    ),
    (
      stop: AdminMapStop.passwords,
      icon: QuarkIcons.lock_outline,
      title: 'Passwords',
      what:
          'Each account has a vault of its own. Nobody else can open it, '
          'an admin included.',
      where: 'Vault',
      route: AppRoutes.vault,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        key: const ValueKey('admin_map'),
        leading: const Icon(QuarkIcons.info_outline),
        title: const Text(
          'Where things live',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: const Text(
          'People, folder access, clients, disks and passwords',
        ),
        children: [
          for (final s in _stops)
            ListTile(
              key: ValueKey('admin_map_${s.stop.name}'),
              leading: Icon(s.icon),
              title: Text(s.title),
              subtitle: Text(
                '${s.what}\n${s.stop == here ? 'You are here' : s.where}',
              ),
              isThreeLine: true,
              trailing: s.stop == here
                  ? null
                  : const Icon(QuarkIcons.chevron_right),
              onTap: s.stop == here ? null : () => context.go(s.route),
            ),
        ],
      ),
    );
  }
}
