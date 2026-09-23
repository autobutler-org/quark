import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../core/quark_loader.dart';
import '../../models/group_item.dart';
import '../../theme/quark_tokens.dart';

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
    final tokens = QuarkTokens.of(context);
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

    return ListTile(
      key: ValueKey('group_row_$id'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.group_outlined),
      title: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        details,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: tokens.mutedForeground),
      ),
      trailing: isBusy
          ? const QuarkLoader(size: 24)
          : actions.isEmpty
          ? null
          : PopupMenuButton<VoidCallback>(
              key: ValueKey('group_menu_$id'),
              tooltip: 'Actions for ${group.name}',
              icon: const Icon(QuarkIcons.more_vert),
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                for (final (action, label, callback) in actions)
                  PopupMenuItem(
                    key: ValueKey('group_action_${action}_$id'),
                    value: callback,
                    child: Text(
                      label,
                      style: action == 'delete'
                          ? TextStyle(color: tokens.error)
                          : null,
                    ),
                  ),
              ],
            ),
    );
  }
}
