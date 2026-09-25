import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../core/quark_loader.dart';
import '../models/chat_channel_item.dart';
import '../theme/quark_tokens.dart';
import 'quark_channel_list/chat_channel_tile.dart';

/// A chat server's channels under the server's name, the open one
/// highlighted and the private ones marked with a lock. [otherChannels], the
/// ones an admin manages without being in them, follow under their own
/// heading.
///
/// Which channel is open is the caller's: [selectedChannelId] in, [onSelect]
/// out. Loading, the error and the empty list are the caller's to decide too,
/// and each renders on its own under the server name. The list fills its
/// parent and scrolls on its own, so it sits in a pane or a drawer.
///
/// Key prefixes: `channel_list_header` on the server name,
/// `channel_list_other_header` on the other channels' heading, and
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
    this.otherChannels = const [],
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

  /// Channels listed apart, under "Other channels": for an admin, the ones
  /// they can manage but are not in. Empty shows no heading.
  final List<ChatChannelItem> otherChannels;

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
        else ...[
          for (final channel in channels)
            ChatChannelTile(
              channel: channel,
              isSelected: channel.id == selectedChannelId,
              onSelect: onSelect,
            ),
          if (otherChannels.isNotEmpty)
            Padding(
              key: const ValueKey('channel_list_other_header'),
              padding: EdgeInsets.fromLTRB(
                tokens.spacingSm,
                tokens.spacingMd,
                tokens.spacingSm,
                tokens.spacingXs,
              ),
              child: Text(
                'Other channels',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: tokens.mutedForeground,
                ),
              ),
            ),
          for (final channel in otherChannels)
            ChatChannelTile(
              channel: channel,
              isSelected: channel.id == selectedChannelId,
              onSelect: onSelect,
            ),
        ],
      ],
    );
  }
}
