import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../core/quark_loader.dart';
import '../models/group_item.dart';
import '../theme/quark_tokens.dart';
import 'group_list/group_row.dart';

/// The groups on a Quark, one row each with how many accounts are in it, the
/// actions an admin can take on a group in a menu at the end of its row, and
/// a button for a new group.
///
/// Loading, the error and the empty list are the caller's to decide, and each
/// renders in place of the rows; the new-group button stays. The list lays
/// out as a column rather than scrolling itself, so it sits in a page's own
/// scroll view.
///
/// A built-in group, such as `everyone`, reads "Every account" and has no
/// menu: its members are every account, and it cannot be renamed or
/// deleted. An action whose callback is null is left out of every menu, and
/// a null [onCreate] leaves the button out.
///
/// Key prefixes: `group_create` on the new-group button, `group_row_<id>` on
/// each row, `group_menu_<id>` on its menu button, and
/// `group_action_<action>_<id>` on the menu entries, where the action is
/// `members`, `rename` or `delete`.
///
/// ```dart
/// GroupList(
///   groups: controller.groups,
///   isLoading: controller.isLoading,
///   error: loadError,
///   busyIds: controller.busyGroupIds,
///   onCreate: openCreateDialog,
///   onMembers: openMembers,
///   onRename: openRenameDialog,
///   onDelete: confirmDelete,
/// );
/// ```
class GroupList extends StatelessWidget {
  /// Creates the list of [groups].
  const GroupList({
    required this.groups,
    this.isLoading = false,
    this.error,
    this.busyIds = const {},
    this.onCreate,
    this.onMembers,
    this.onRename,
    this.onDelete,
    super.key,
  });

  /// The groups to list, in the order they are shown.
  final List<GroupItem> groups;

  /// Whether the groups are still loading. Shows a spinner in place of the
  /// rows.
  final bool isLoading;

  /// A sentence saying why the groups could not be loaded, composed by the
  /// caller. Shown in place of the rows.
  final String? error;

  /// Ids of groups with an action in flight. Their rows show progress in
  /// place of the menu.
  final Set<int> busyIds;

  /// Called when the new-group button is tapped. Null leaves the button out.
  final VoidCallback? onCreate;

  /// Called with the id of the group whose members to show. Null leaves the
  /// entry out.
  final ValueChanged<int>? onMembers;

  /// Called with the id of the group to rename. Null leaves the entry out.
  final ValueChanged<int>? onRename;

  /// Called with the id of the group to delete; the caller confirms before
  /// deleting. Null leaves the entry out.
  final ValueChanged<int>? onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = this.error;

    VoidCallback? bind(ValueChanged<int>? callback, int id) =>
        callback == null ? null : () => callback(id);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onCreate != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              key: const ValueKey('group_create'),
              onPressed: onCreate,
              icon: const Icon(QuarkIcons.add),
              label: const Text('New group'),
            ),
          ),
        if (isLoading)
          Padding(
            padding: EdgeInsets.all(tokens.spacingLg),
            child: const Center(child: QuarkLoader()),
          )
        else if (error != null)
          Padding(
            padding: EdgeInsets.symmetric(vertical: tokens.spacingMd),
            child: Text(error, style: TextStyle(color: tokens.error)),
          )
        else if (groups.isEmpty)
          const EmptyStateWidget(
            icon: Icons.group_outlined,
            headline: 'No groups yet',
          )
        else
          for (final group in groups)
            GroupRow(
              group: group,
              isBusy: busyIds.contains(group.id),
              onMembers: bind(onMembers, group.id),
              onRename: bind(onRename, group.id),
              onDelete: bind(onDelete, group.id),
            ),
      ],
    );
  }
}
