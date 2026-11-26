import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

import 'chat_demo_data.dart';
import 'framed_viewport.dart';

/// Shows [QuarkChatLayout] wide and narrow at once, composed from the real
/// chat widgets, and holds the drawer, sheet, side conversation, channel and
/// expansion state the widgets refuse to hold: the gallery is the caller. It
/// opens with a side conversation open.
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
  double _channelWidth = QuarkChatLayout.channelListWidth;
  double _memberWidth = QuarkChatLayout.memberListWidth;
  bool _channelsCollapsed = false;
  bool _membersCollapsed = false;
  String? _branchId = 'm6';
  double _branchWidth = QuarkChatLayout.branchWidth;

  void _closeBranch() {
    widget.log('QuarkBranchPanel.onClose');
    setState(() => _branchId = null);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final theme = Theme.of(context);
    final branchId = _branchId;
    final branchParent = galleryChatMessages
        .where((m) => m.id == branchId)
        .firstOrNull;
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
              permissions: ChatPermissionPreset.moderator.permissions,
              currentUserId: galleryChatUserId,
              onDelete: (id) => widget.log('QuarkMessageList.onDelete($id)'),
              onOpenBranch: (id) {
                widget.log('QuarkMessageList.onOpenBranch($id)');
                setState(() => _branchId = id);
              },
              onOpenLink: (uri) =>
                  widget.log('QuarkMessageList.onOpenLink($uri)'),
              onOpenAttachment: (id, item) => widget.log(
                'QuarkMessageList.onOpenAttachment($id, ${item.id})',
              ),
              onPlayAttachment: (id, item) => widget.log(
                'QuarkMessageList.onPlayAttachment($id, ${item.id})',
              ),
              onSaveAttachmentToDevice: (id, item) => widget.log(
                'QuarkMessageList.onSaveAttachmentToDevice($id, ${item.id})',
              ),
              onSaveAttachmentToFiles: (id, item) => widget.log(
                'QuarkMessageList.onSaveAttachmentToFiles($id, ${item.id})',
              ),
              thumbnailBuilder: (context, item) => ColoredBox(
                color: QuarkTokens.of(context).primary,
                child: const SizedBox(width: 120, height: 80),
              ),
              onAtBottomChanged: (atBottom) =>
                  widget.log('QuarkMessageList.onAtBottomChanged($atBottom)'),
            ),
          ),
          QuarkMessageComposer(
            hintText: 'Message #$_channelId',
            permissions: ChatPermissionPreset.moderator.permissions,
            onSend: (text) => widget.log('QuarkMessageComposer.onSend($text)'),
            onAttach: () => widget.log('QuarkMessageComposer.onAttach'),
          ),
        ],
      ),
      memberList: QuarkMemberList(
        members: galleryChatMembers,
        permissions: ChatPermissionPreset.moderator.permissions,
        onAddMembers: () => widget.log('QuarkMemberList.onAddMembers'),
        onRemove: (id) => widget.log('QuarkMemberList.onRemove($id)'),
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
      branch: branchId == null
          ? null
          : QuarkBranchPanel(
              parent: branchParent,
              onClose: _closeBranch,
              messages: QuarkMessageList(
                messages: galleryBranchReplies,
                isBranch: true,
                permissions: ChatPermissionPreset.moderator.permissions,
                currentUserId: galleryChatUserId,
                onDelete: (id) => widget.log('QuarkMessageList.onDelete($id)'),
              ),
              composer: QuarkMessageComposer(
                hintText: 'Reply',
                permissions: ChatPermissionPreset.moderator.permissions,
                onSend: (text) =>
                    widget.log('QuarkMessageComposer.onSend($text)'),
              ),
            ),
      branchTitle: QuarkBranchPanel.titleFor(branchParent),
      onCloseBranch: _closeBranch,
      branchPaneWidth: _branchWidth,
      onBranchPaneWidthChanged: (width) {
        widget.log(
          'QuarkChatLayout.onBranchPaneWidthChanged(${width.round()})',
        );
        setState(() => _branchWidth = width);
      },
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
      channelPaneWidth: _channelWidth,
      isChannelPaneCollapsed: _channelsCollapsed,
      onChannelPaneWidthChanged: (width) {
        widget.log(
          'QuarkChatLayout.onChannelPaneWidthChanged(${width.round()})',
        );
        setState(() => _channelWidth = width);
      },
      onChannelPaneCollapsedChanged: (collapsed) {
        widget.log('QuarkChatLayout.onChannelPaneCollapsedChanged($collapsed)');
        setState(() => _channelsCollapsed = collapsed);
      },
      memberPaneWidth: _memberWidth,
      isMemberPaneCollapsed: _membersCollapsed,
      onMemberPaneWidthChanged: (width) {
        widget.log(
          'QuarkChatLayout.onMemberPaneWidthChanged(${width.round()})',
        );
        setState(() => _memberWidth = width);
      },
      onMemberPaneCollapsedChanged: (collapsed) {
        widget.log('QuarkChatLayout.onMemberPaneCollapsedChanged($collapsed)');
        setState(() => _membersCollapsed = collapsed);
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Above the breakpoint: channels, messages and members side by side, '
          'or a side conversation in the members\' place; drag a pane\'s '
          'edge to resize it, or use the header buttons',
          style: theme.textTheme.titleSmall,
        ),
        SizedBox(height: tokens.spacingSm),
        FramedViewport(width: 1100, height: 520, child: layout),
        SizedBox(height: tokens.spacingLg),
        Text(
          'Below it: messages alone; the buttons open the channel drawer and '
          'the member sheet, and a side conversation opens as a sheet',
          style: theme.textTheme.titleSmall,
        ),
        SizedBox(height: tokens.spacingSm),
        FramedViewport(width: 360, height: 640, child: layout),
      ],
    );
  }
}
