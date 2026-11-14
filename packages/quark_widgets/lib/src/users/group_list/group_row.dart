import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../core/quark_menu_row.dart';
import '../../models/group_item.dart';
import '../../models/quark_menu_entry.dart';

/// One group in a [GroupList]: its name, who is in it, and a menu of the
/// actions on offer.
///
/// A part of [GroupList], tested through it.
///
/// Key prefixes: `group_row_<id>`, `group_menu_<id>`, and
/// `group_action_<action>_<id>` on each menu entry.
class GroupRow extends StatelessWidget {
  /// Creates the row for [group].
  const GroupRow({
    required this.group,
    this.isBusy = false,
    this.onMembers,
    this.onRename,
    this.onDelete,
    super.key,
  });

  /// The group this row shows.
  final GroupItem group;

  /// Whether an action on this group is in flight.
  final bool isBusy;

  /// Shows the group's members. Never offered on a built-in group; null
  /// leaves it out.
  final VoidCallback? onMembers;

  /// Renames the group. Never offered on a built-in group; null leaves it
  /// out.
  final VoidCallback? onRename;

  /// Deletes the group. Never offered on a built-in group; null leaves it
  /// out.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final id = group.id;
    final count = group.members.length;

    final actions = group.isBuiltin
        ? const <(String, String, VoidCallback)>[]
        : <(String, String, VoidCallback)>[
            if (onMembers != null) ('members', 'Members', onMembers!),
            if (onRename != null) ('rename', 'Rename', onRename!),
            if (onDelete != null) ('delete', 'Delete', onDelete!),
          ];

    final details = group.isBuiltin
        ? 'Every account'
        : switch (count) {
            0 => 'No members',
            1 => '1 member',
            _ => '$count members',
          };

    final entries = [
      for (final (action, label, callback) in actions)
        QuarkMenuEntry(
          key: ValueKey('group_action_${action}_$id'),
          label: label,
          destructive: action == 'delete',
          onSelected: callback,
        ),
    ];
    return QuarkMenuRow(
      key: ValueKey('group_row_$id'),
      menuKey: ValueKey('group_menu_$id'),
      leading: const Icon(QuarkIcons.group_outlined),
      title: group.name,
      subtitle: details,
      busy: isBusy,
      menuTooltip: 'Actions for ${group.name}',
      entries: entries,
    );
  }
}
