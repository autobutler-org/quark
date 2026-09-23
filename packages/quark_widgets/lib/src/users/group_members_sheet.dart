import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/quark_loader.dart';
import '../models/group_item.dart';
import '../models/principal_item.dart';
import '../theme/quark_tokens.dart';
import 'principal_picker.dart';

/// The members of one group, a button to remove each, and a picker to add an
/// account.
///
/// Membership is the caller's: [group] in with its members, [onAdd] and
/// [onRemove] out, and the caller refreshes [group] once the change lands.
/// The picker offers [candidates] less the accounts already in the group.
/// A member with a change in flight, in [busyIds], shows progress in place of
/// its remove button, and a refusal comes back in as [error].
///
/// Meant for a group whose members can change, never a built-in one. Show it
/// with `showModalBottomSheet(isScrollControlled: true, ...)`: it scrolls
/// itself and moves clear of the keyboard.
///
/// Key prefixes: `group_member_<userId>` on each member row,
/// `group_member_remove_<userId>` on its remove button, and the
/// [PrincipalPicker] keys, `principal_search` and
/// `principal_option_user_<userId>`.
///
/// ```dart
/// showModalBottomSheet<void>(
///   context: context,
///   isScrollControlled: true,
///   builder: (context) => GroupMembersSheet(
///     group: group,
///     candidates: activeAccounts,
///     busyIds: controller.busyMemberIds,
///     error: memberError,
///     onAdd: (userId) => controller.addMember(group.id, userId),
///     onRemove: (userId) => controller.removeMember(group.id, userId),
///   ),
/// );
/// ```
class GroupMembersSheet extends StatelessWidget {
  /// Creates the sheet for [group].
  const GroupMembersSheet({
    required this.group,
    required this.candidates,
    this.busyIds = const {},
    this.error,
    this.onAdd,
    this.onRemove,
    super.key,
  });

  /// The group, with the members to list.
  final GroupItem group;

  /// The accounts that may join a group. Those already in it are left out of
  /// the picker.
  final List<PrincipalItem> candidates;

  /// Ids of accounts with an add or a remove in flight.
  final Set<int> busyIds;

  /// A sentence saying why the last change was refused, composed by the
  /// caller. Shown under the title.
  final String? error;

  /// Called with the id of the account to add. Null leaves the picker out.
  final ValueChanged<int>? onAdd;

  /// Called with the id of the member to remove. Null disables the remove
  /// buttons.
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QuarkTokens.of(context);
    final error = this.error;
    final onAdd = this.onAdd;
    final onRemove = this.onRemove;
    final memberIds = {for (final member in group.members) member.id};

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(tokens.spacingMd),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Members of ${group.name}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (error != null) ...[
                SizedBox(height: tokens.spacingSm),
                Text(error, style: TextStyle(color: tokens.error)),
              ],
              SizedBox(height: tokens.spacingSm),
              if (group.members.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: tokens.spacingSm),
                  child: Text(
                    'No members yet',
                    style: TextStyle(color: tokens.mutedForeground),
                  ),
                )
              else
                for (final member in group.members)
                  ListTile(
                    key: ValueKey('group_member_${member.id}'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(QuarkIcons.person_outline),
                    title: Text(
                      member.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: busyIds.contains(member.id)
                        ? const QuarkLoader(size: 24)
                        : IconButton(
                            key: ValueKey('group_member_remove_${member.id}'),
                            tooltip: 'Remove ${member.name}',
                            icon: const Icon(QuarkIcons.close),
                            onPressed: onRemove == null
                                ? null
                                : () => onRemove(member.id),
                          ),
                  ),
              if (onAdd != null) ...[
                SizedBox(height: tokens.spacingMd),
                Text(
                  'Add a member',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: tokens.spacingSm),
                PrincipalPicker(
                  options: [
                    for (final candidate in candidates)
                      if (!memberIds.contains(candidate.id)) candidate,
                  ],
                  searchLabel: 'Search accounts',
                  onSelected: (account) => onAdd(account.id),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
