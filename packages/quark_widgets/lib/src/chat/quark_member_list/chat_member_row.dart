import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../core/quark_avatar.dart';
import '../../models/chat_member_item.dart';
import '../../theme/quark_tokens.dart';

/// One row of a `QuarkMemberList`: an account with its avatar, or a group
/// with a chevron that shows whether its accounts are listed under it.
///
/// A part of `QuarkMemberList`, tested through it.
class ChatMemberRow extends StatelessWidget {
  /// Creates the row for [member].
  const ChatMemberRow({
    required this.member,
    this.avatarBuilder,
    this.avatarSize = QuarkAvatar.defaultSize,
    this.isExpanded = false,
    this.indent = 0,
    this.onTap,
    super.key,
  });

  /// The member this row shows.
  final ChatMemberItem member;

  /// Builds an account's avatar from its id. Null draws a [QuarkAvatar]
  /// with its initials. Groups draw a group glyph instead.
  final Widget Function(BuildContext context, String userId)? avatarBuilder;

  /// The diameter of the avatar.
  final double avatarSize;

  /// Whether a group's accounts are listed under it. Ignored for an account.
  final bool isExpanded;

  /// The extra leading padding, for an account listed under its group.
  final double indent;

  /// Called when the row is tapped. Null makes it inert.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final level = member.level;
    final avatarBuilder = this.avatarBuilder;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsetsDirectional.only(
        start: tokens.spacingSm + indent,
        end: tokens.spacingSm,
      ),
      minLeadingWidth: 0,
      leading: SizedBox.square(
        dimension: avatarSize,
        child: member.isGroup
            ? Icon(QuarkIcons.group_outlined, color: tokens.secondaryForeground)
            : avatarBuilder != null
            ? avatarBuilder(context, member.id)
            : QuarkAvatar(id: member.id, name: member.name, size: avatarSize),
      ),
      title: Text(
        member.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: tokens.foreground),
      ),
      subtitle: level == null
          ? null
          : Text(
              level.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.mutedForeground),
            ),
      trailing: member.isGroup
          ? Icon(
              isExpanded ? QuarkIcons.expand_less : QuarkIcons.expand_more,
              color: tokens.secondaryForeground,
            )
          : null,
      onTap: onTap,
    );
  }
}
