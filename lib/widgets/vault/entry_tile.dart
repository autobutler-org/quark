import 'package:flutter/material.dart';
import 'package:quark/services/vault_service.dart';
import 'package:quark_icons/quark_icons.dart';

/// One vault entry in the entry list.
class EntryTile extends StatelessWidget {
  final VaultEntryItem entry;
  final VoidCallback onTap;

  const EntryTile({super.key, required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        child: Text(entry.name.isNotEmpty ? entry.name[0].toUpperCase() : '?'),
      ),
      title: Text(entry.name),
      subtitle: entry.urlHost.isNotEmpty ? Text(entry.urlHost) : null,
      trailing: const Icon(QuarkIcons.chevron_right),
      onTap: onTap,
    );
  }
}
