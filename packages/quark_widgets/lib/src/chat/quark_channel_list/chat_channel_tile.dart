import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../models/chat_channel_item.dart';
import '../../models/chat_permission_preset.dart';
import '../../theme/quark_tokens.dart';
import 'chat_unread_pill.dart';

/// One channel in a `QuarkChannelList`: its name after a `#`, highlighted
/// when open, with a lock when it is private and, when it has
/// [ChatChannelItem.permissions], what the signed-in account may do there as
/// a preset or Custom. A channel with a [ChatChannelItem.unreadCount] above
/// zero draws its name in bold and the count in a pill at its end, `99+`
/// above 99.
///
/// A part of `QuarkChannelList`, tested through it. Keys: `channel_tile_<id>`
/// on the row and `channel_unread_<id>` on its unread count.
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
    final pill = ChatUnreadPill(
      key: ValueKey('channel_unread_${channel.id}'),
      count: channel.unreadCount,
    );
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
      leading: const Icon(QuarkIcons.tag, size: 18),
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
      trailing: switch ((hasUnread, channel.isPrivate)) {
        (false, false) => null,
        (false, true) => lock,
        (true, false) => pill,
        (true, true) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            pill,
            SizedBox(width: tokens.spacingSm),
            lock,
          ],
        ),
      },
      onTap: onSelect == null ? null : () => onSelect(channel.id),
    );
  }
}
