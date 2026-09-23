import 'package:flutter/material.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark_icons/quark_icons.dart';

/// Which Quark these credentials are for, plus the way out if it is the
/// wrong one — without this the user is stuck on the login page (#1639).
///
/// Collapsed, it shows that Quark's name and address. While the host list
/// is open it is only the heading and the button, so the selected Quark is
/// not listed a second time on its own radio (#2069).
class ActiveHostCard extends StatelessWidget {
  final bool managingHosts;
  final VoidCallback onToggleManagingHosts;

  const ActiveHostCard({
    super.key,
    required this.managingHosts,
    required this.onToggleManagingHosts,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = AppSettings.instance;
    final hosts = settings.hosts;
    final index = settings.activeIndex;
    final active = (index >= 0 && index < hosts.length) ? hosts[index] : null;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          QuarkIcons.storage_outlined,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          managingHosts ? 'Choose a Quark' : (active?.name ?? 'Quark'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: managingHosts ? null : Text(active?.hostAddress ?? ''),
        trailing: TextButton(
          onPressed: onToggleManagingHosts,
          child: Text(managingHosts ? 'Done' : 'Change'),
        ),
      ),
    );
  }
}
