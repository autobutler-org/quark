import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../models/vault_entry_item.dart';

/// One row of `VaultEntryList`: the entry's initial, name and subtitle.
///
/// Key prefixes: `vault_entry_<id>`.
class VaultEntryTile extends StatelessWidget {
  /// Creates the row for [entry].
  const VaultEntryTile({required this.entry, required this.onTap, super.key});

  /// The entry shown.
  final VaultEntryItem entry;

  /// Called when the row is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = entry.name.trim();
    return ListTile(
      key: ValueKey('vault_entry_${entry.id}'),
      leading: CircleAvatar(
        child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase()),
      ),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: entry.subtitle.isEmpty
          ? null
          : Text(entry.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(QuarkIcons.chevron_right),
      onTap: onTap,
    );
  }
}
