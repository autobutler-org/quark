import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../models/chat_channel_item.dart';
import '../../models/chat_permission_preset.dart';
import '../../theme/quark_tokens.dart';
import 'chat_unread_pill.dart';

/// One channel in a `QuarkChannelList`: its name after a `#`, or after a
/// person for a [ChatChannelItem.isDirect] conversation, highlighted
/// when open, with a lock when it is private and, when it has
/// [ChatChannelItem.permissions], what the signed-in account may do there as
/// a preset or Custom. A channel with a [ChatChannelItem.unreadCount] above
/// zero draws its name in bold and the count in a pill at its end, `99+`
/// above 99. One with a [ChatChannelItem.mentionCount] above zero has a
/// second pill before it, reading `@` and how many of them mention the
/// signed-in account.
///
/// A part of `QuarkChannelList`, tested through it. Keys: `channel_tile_<id>`
/// on the row, `channel_unread_<id>` on its unread count and
/// `channel_mention_<id>` on its unread mentions.
class ChatChannelTile extends StatelessWidget {
  /// Creates the tile for [channel].
  const ChatChannelTile({
    required this.channel,
    this.isSelected = false,
    this.onSelect,
    super.key,
  });

  /// The channel this tile shows.
  final ChatChannelItem channel;

  /// Whether it is the open channel.
  final bool isSelected;

  /// Called with the channel's id when tapped. Null makes the tile inert.
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final onSelect = this.onSelect;
    final permissions = channel.permissions;
    final hasUnread = channel.unreadCount > 0;
    final lock = Tooltip(
      message: 'Private channel',
      child: Icon(
        QuarkIcons.lock_outline,
        size: 16,
        color: tokens.mutedForeground,
      ),
    );
    final trailing = [
      if (channel.mentionCount > 0)
        ChatUnreadPill(
          key: ValueKey('channel_mention_${channel.id}'),
          count: channel.mentionCount,
          isMention: true,
        ),
      if (channel.unreadCount > 0)
        ChatUnreadPill(
          key: ValueKey('channel_unread_${channel.id}'),
          count: channel.unreadCount,
        ),
      if (channel.isPrivate) lock,
    ];
    return ListTile(
      key: ValueKey('channel_tile_${channel.id}'),
      dense: true,
      selected: isSelected,
      selectedColor: tokens.primary,
      selectedTileColor: tokens.primary.withValues(alpha: 0.12),
      iconColor: tokens.secondaryForeground,
      textColor: tokens.foreground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      leading: Icon(
        channel.isDirect ? QuarkIcons.person_outline : QuarkIcons.tag,
        size: 18,
      ),
      minLeadingWidth: 0,
      title: Text(
        channel.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: hasUnread ? const TextStyle(fontWeight: FontWeight.w700) : null,
      ),
      subtitle: permissions == null
          ? null
          : Text(
              ChatPermissionPreset.labelOf(permissions),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.mutedForeground, fontSize: 12),
            ),
      trailing: trailing.isEmpty
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              spacing: tokens.spacingSm,
              children: trailing,
            ),
      onTap: onSelect == null ? null : () => onSelect(channel.id),
    );
  }
}
