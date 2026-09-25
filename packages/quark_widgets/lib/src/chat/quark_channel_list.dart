import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../core/quark_loader.dart';
import '../models/chat_channel_item.dart';
import '../theme/quark_tokens.dart';

/// A chat server's channels under the server's name, the open one
/// highlighted and the private ones marked with a lock.
///
/// Which channel is open is the caller's: [selectedChannelId] in, [onSelect]
/// out. Loading, the error and the empty list are the caller's to decide too,
/// and each renders on its own under the server name. The list fills its
/// parent and scrolls on its own, so it sits in a pane or a drawer.
///
/// Key prefixes: `channel_list_header` on the server name and
/// `channel_tile_<id>` on each channel.
///
/// ```dart
/// QuarkChannelList(
///   serverName: controller.serverName,
///   channels: controller.channels,
///   selectedChannelId: controller.channelId,
///   isLoading: controller.isLoadingChannels,
///   error: channelsError,
///   onSelect: openChannel,
/// );
/// ```
class QuarkChannelList extends StatelessWidget {
  /// Creates the list of [channels] on [serverName].
  const QuarkChannelList({
    required this.serverName,
    required this.channels,
    this.selectedChannelId,
    this.isLoading = false,
    this.error,
    this.onSelect,
    super.key,
  });

  /// The server the channels belong to, shown as the list's heading.
  final String serverName;

  /// The channels, in the order they are shown.
  final List<ChatChannelItem> channels;

  /// The id of the open channel, highlighted. Null highlights nothing.
  final String? selectedChannelId;

  /// Whether the channels are still loading. Shows a spinner in place of
  /// them.
  final bool isLoading;

  /// A sentence saying why the channels could not be loaded, composed by the
  /// caller. Shown in place of them.
  final String? error;

  /// Called with the id of the channel that was tapped. Null makes the rows
  /// inert.
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final theme = Theme.of(context);
    final error = this.error;
    final onSelect = this.onSelect;

    return ListView(
      padding: EdgeInsets.all(tokens.spacingSm),
      children: [
        Padding(
          key: const ValueKey('channel_list_header'),
          padding: EdgeInsets.all(tokens.spacingSm),
          child: Text(
            serverName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              color: tokens.foreground,
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
            padding: EdgeInsets.all(tokens.spacingMd),
            child: Text(error, style: TextStyle(color: tokens.error)),
          )
        else if (channels.isEmpty)
          const EmptyStateWidget(
            icon: QuarkIcons.forum_outlined,
            headline: 'No channels yet',
          )
        else
          for (final channel in channels)
            ListTile(
              key: ValueKey('channel_tile_${channel.id}'),
              dense: true,
              selected: channel.id == selectedChannelId,
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
              ),
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
            ),
      ],
    );
  }
}
