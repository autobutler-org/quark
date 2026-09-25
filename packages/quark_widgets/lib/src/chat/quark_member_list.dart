import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../core/quark_loader.dart';
import '../models/chat_member_item.dart';
import '../theme/quark_tokens.dart';
import 'quark_member_list/chat_member_row.dart';

/// The people in a chat channel: accounts with their avatars, and groups the
/// channel is shared with, each of which expands to list its accounts.
///
/// Which groups are expanded is the caller's: [expandedIds] in,
/// [onToggleExpanded] out. Loading, the error and the empty list are the
/// caller's to decide too. The list fills its parent and scrolls on its own,
/// so it sits in a pane or a sheet.
///
/// Key prefixes: `member_row_<id>` on each top-level row, where tapping a
/// group's row expands or collapses it, and `member_row_<groupId>_<id>` on an
/// account listed under an expanded group.
///
/// ```dart
/// QuarkMemberList(
///   members: controller.members,
///   expandedIds: controller.expandedGroupIds,
///   onToggleExpanded: controller.toggleGroup,
///   avatarBuilder: (context, userId) => AppAvatar(userId: userId),
/// );
/// ```
class QuarkMemberList extends StatelessWidget {
  /// Creates the list of [members].
  const QuarkMemberList({
    required this.members,
    this.expandedIds = const {},
    this.onToggleExpanded,
    this.avatarBuilder,
    this.isLoading = false,
    this.error,
    super.key,
  });

  /// The diameter of each avatar.
  static const double avatarSize = 28;

  /// The members, in the order they are shown.
  final List<ChatMemberItem> members;

  /// The ids of the groups whose accounts are listed under them.
  final Set<String> expandedIds;

  /// Called with a group's id when its row is tapped, with the caller
  /// expected to add it to or remove it from [expandedIds]. Null makes group
  /// rows inert.
  final ValueChanged<String>? onToggleExpanded;

  /// Builds the avatar for an account's id, [avatarSize] across. Null draws
  /// a `QuarkAvatar` with the account's initials.
  final Widget Function(BuildContext context, String userId)? avatarBuilder;

  /// Whether the members are still loading. Shows a spinner in place of
  /// them.
  final bool isLoading;

  /// A sentence saying why the members could not be loaded, composed by the
  /// caller. Shown in place of them.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = this.error;
    final onToggleExpanded = this.onToggleExpanded;
    final avatarBuilder = this.avatarBuilder;

    return ListView(
      padding: EdgeInsets.all(tokens.spacingSm),
      children: [
        Padding(
          padding: EdgeInsets.all(tokens.spacingSm),
          child: Text(
            'Members',
            style: TextStyle(
              color: tokens.secondaryForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (isLoading)
          Padding(
            padding: EdgeInsets.all(tokens.spacingLg),
            child: const Center(child: QuarkLoader()),
          )
        else if (error != null)
          Padding(
            padding: EdgeInsets.all(tokens.spacingSm),
            child: Text(error, style: TextStyle(color: tokens.error)),
          )
        else if (members.isEmpty)
          const EmptyStateWidget(
            icon: QuarkIcons.group_outlined,
            headline: 'No members yet',
          )
        else
          for (final member in members) ...[
            ChatMemberRow(
              key: ValueKey('member_row_${member.id}'),
              member: member,
              avatarBuilder: avatarBuilder,
              avatarSize: avatarSize,
              isExpanded: expandedIds.contains(member.id),
              onTap: member.isGroup && onToggleExpanded != null
                  ? () => onToggleExpanded(member.id)
                  : null,
            ),
            if (member.isGroup && expandedIds.contains(member.id))
              for (final inner in member.members)
                ChatMemberRow(
                  key: ValueKey('member_row_${member.id}_${inner.id}'),
                  member: inner,
                  avatarBuilder: avatarBuilder,
                  avatarSize: avatarSize,
                  indent: tokens.spacingLg,
                ),
          ],
      ],
    );
  }
}
