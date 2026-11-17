import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../core/quark_menu_button.dart';
import '../../models/quark_menu_entry.dart';
import '../../models/vault_entry_item.dart';
import '../../theme/quark_tokens.dart';

/// One row of `VaultEntryList`: a key tile, the entry's name, a muted line
/// with its site and username, and, with [onAction] set, a ⋮ menu to copy the
/// password or username, edit, or delete it (#4234).
///
/// Key prefixes: `vault_entry_<id>` on the row, `vault_entry_menu_<id>` on its
/// menu button, and `vault_entry_<action>_<id>` on the menu's rows, where
/// `<action>` is a [VaultEntryAction] name such as `copyPassword`.
class VaultEntryTile extends StatelessWidget {
  /// Creates the row for [entry].
  const VaultEntryTile({
    required this.entry,
    required this.onTap,
    this.onAction,
    super.key,
  });

  /// The entry shown.
  final VaultEntryItem entry;

  /// Called when the row is tapped.
  final VoidCallback onTap;

  /// Called with the menu row chosen. Null hides the menu.
  final ValueChanged<VaultEntryAction>? onAction;

  static const _labels = {
    VaultEntryAction.copyPassword: 'Copy password',
    VaultEntryAction.copyUsername: 'Copy username',
    VaultEntryAction.edit: 'Edit',
    VaultEntryAction.delete: 'Delete',
  };

  static const _icons = {
    VaultEntryAction.copyPassword: QuarkIcons.content_copy,
    VaultEntryAction.copyUsername: QuarkIcons.content_copy,
    VaultEntryAction.edit: QuarkIcons.edit_outlined,
    VaultEntryAction.delete: QuarkIcons.delete_outline,
  };

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final onAction = this.onAction;
    return ListTile(
      key: ValueKey('vault_entry_${entry.id}'),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: tokens.input,
          border: Border.all(color: tokens.border),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
        child: Icon(QuarkIcons.key, size: 18, color: tokens.foreground),
      ),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: entry.subtitle.isEmpty
          ? null
          : Text(
              entry.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.mutedForeground),
            ),
      trailing: onAction == null
          ? const Icon(QuarkIcons.chevron_right)
          : QuarkMenuButton(
              key: ValueKey('vault_entry_menu_${entry.id}'),
              tooltip: 'Actions for ${entry.name}',
              entries: [
                for (final action in VaultEntryAction.values)
                  QuarkMenuEntry(
                    key: ValueKey('vault_entry_${action.name}_${entry.id}'),
                    label: _labels[action]!,
                    icon: _icons[action],
                    destructive: action == VaultEntryAction.delete,
                    onSelected: () => onAction(action),
                  ),
              ],
            ),
      onTap: onTap,
    );
  }
}
