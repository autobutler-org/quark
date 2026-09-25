import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../models/chat_channel_item.dart';
import '../../theme/quark_tokens.dart';

/// One channel in a `QuarkChannelList`: its name after a `#`, highlighted
/// when open, with a lock when it is private.
///
/// A part of `QuarkChannelList`, tested through it. Key: `channel_tile_<id>`.
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
      title: Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: channel.isPrivate
          ? Tooltip(
              message: 'Private channel',
              child: Icon(
                QuarkIcons.lock_outline,
                size: 16,
                color: tokens.mutedForeground,
              ),
            )
          : null,
      onTap: onSelect == null ? null : () => onSelect(channel.id),
    );
  }
}
