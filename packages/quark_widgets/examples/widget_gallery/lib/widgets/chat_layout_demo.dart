import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

import 'chat_demo_data.dart';
import 'framed_viewport.dart';

/// Shows [QuarkChatLayout] wide and narrow at once, composed from the real
/// chat widgets, and holds the drawer, sheet, channel and expansion state the
/// widgets refuse to hold: the gallery is the caller.
class ChatLayoutDemo extends StatefulWidget {
  /// Creates the example, logging every callback through [log].
  const ChatLayoutDemo({required this.log, super.key});

  /// The gallery's event panel.
  final void Function(String event) log;

  @override
  State<ChatLayoutDemo> createState() => _ChatLayoutDemoState();
}

class _ChatLayoutDemoState extends State<ChatLayoutDemo> {
  String _channelId = 'general';
  bool _channelsOpen = false;
  bool _membersOpen = false;
  Set<String> _expanded = const {};

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final theme = Theme.of(context);
    // One configuration, shown in both frames.
    final layout = QuarkChatLayout(
      header: Text(
        '# $_channelId',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      channelList: QuarkChannelList(
        serverName: 'Lovelace home',
        channels: galleryChatChannels,
        selectedChannelId: _channelId,
        onSelect: (id) {
          widget.log('QuarkChannelList.onSelect($id)');
          setState(() {
            _channelId = id;
            _channelsOpen = false;
          });
        },
      ),
      messages: Column(
        children: [
          Expanded(
            child: QuarkMessageList(
              messages: galleryChatMessages,
              hasMore: true,
              onLoadOlder: () => widget.log('QuarkMessageList.onLoadOlder'),
            ),
          ),
          QuarkMessageComposer(
            hintText: 'Message #$_channelId',
            onSend: (text) => widget.log('QuarkMessageComposer.onSend($text)'),
          ),
        ],
      ),
      memberList: QuarkMemberList(
        members: galleryChatMembers,
        expandedIds: _expanded,
        onToggleExpanded: (id) {
          widget.log('QuarkMemberList.onToggleExpanded($id)');
          setState(
            () => _expanded = _expanded.contains(id)
                ? (_expanded.toSet()..remove(id))
                : {..._expanded, id},
          );
        },
      ),
      isChannelListOpen: _channelsOpen,
      isMemberListOpen: _membersOpen,
      onToggleChannelList: () {
        widget.log('QuarkChatLayout.onToggleChannelList');
        setState(() => _channelsOpen = !_channelsOpen);
      },
      onToggleMemberList: () {
        widget.log('QuarkChatLayout.onToggleMemberList');
        setState(() => _membersOpen = !_membersOpen);
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Above the breakpoint: channels, messages and members side by side',
          style: theme.textTheme.titleSmall,
        ),
        SizedBox(height: tokens.spacingSm),
        FramedViewport(width: 1100, height: 520, child: layout),
        SizedBox(height: tokens.spacingLg),
        Text(
          'Below it: messages alone; the buttons open the channel drawer and '
          'the member sheet',
          style: theme.textTheme.titleSmall,
        ),
        SizedBox(height: tokens.spacingSm),
        FramedViewport(width: 360, height: 640, child: layout),
      ],
    );
  }
}
