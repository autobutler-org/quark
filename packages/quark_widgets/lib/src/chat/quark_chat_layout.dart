import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../layout/quark_bar_icon_button.dart';
import '../layout/quark_split_view.dart';
import '../theme/quark_tokens.dart';

/// The chat page's frame: channels, then messages, then members, side by side
/// on a wide window, and messages alone on a narrow one with the channels in
/// a drawer and the members in a sheet.
///
/// It collapses at the same window width as [QuarkSplitView], so chat
/// changes layout where every other sidebar page does. The split view itself
/// is not reused because it stacks its sidebar into one shared scroll view,
/// and a chat pane is three scroll views of its own.
///
/// The panes are the caller's widgets: usually a `QuarkChannelList`, a
/// `Column` of a `QuarkMessageList` over a `QuarkMessageComposer`, and a
/// `QuarkMemberList`. In the collapsed layout, whether the drawer and the
/// sheet are showing is the caller's too: [isChannelListOpen] and
/// [isMemberListOpen] in, [onToggleChannelList] and [onToggleMemberList] out,
/// fired by the buttons beside [header] and by a tap on the scrim. A caller
/// closes the drawer itself when a channel is picked from it. Nothing slides:
/// the drawer and the sheet appear in place, so there is no motion to reduce.
///
/// Key prefixes: `chat_layout_channels`, `chat_layout_messages` and
/// `chat_layout_members` on the three panes, `chat_layout_channels_toggle`
/// and `chat_layout_members_toggle` on the collapsed layout's buttons, and
/// `chat_layout_scrim` behind an open drawer or sheet.
///
/// ```dart
/// QuarkChatLayout(
///   header: Text('# ${controller.channelName}'),
///   channelList: QuarkChannelList(...),
///   messages: Column(
///     children: [
///       Expanded(child: QuarkMessageList(...)),
///       QuarkMessageComposer(onSend: controller.send),
///     ],
///   ),
///   memberList: QuarkMemberList(...),
///   isChannelListOpen: controller.isChannelDrawerOpen,
///   onToggleChannelList: controller.toggleChannelDrawer,
///   isMemberListOpen: controller.isMemberSheetOpen,
///   onToggleMemberList: controller.toggleMemberSheet,
/// );
/// ```
class QuarkChatLayout extends StatelessWidget {
  /// Creates the frame around [channelList], [messages] and [memberList].
  const QuarkChatLayout({
    required this.channelList,
    required this.messages,
    this.memberList,
    this.header,
    this.isChannelListOpen = false,
    this.isMemberListOpen = false,
    this.onToggleChannelList,
    this.onToggleMemberList,
    super.key,
  });

  /// The width of the channel pane in the wide layout and of the drawer in
  /// the collapsed one.
  static const double channelListWidth = QuarkSplitView.defaultSidebarWidth;

  /// The width of the member pane in the wide layout.
  static const double memberListWidth = 240;

  /// The channel list: a pane when wide, a drawer when collapsed.
  final Widget channelList;

  /// The open channel's messages and composer. Always showing, and given the
  /// remaining height and width.
  final Widget messages;

  /// The member list: a pane when wide, a sheet when collapsed. Null leaves
  /// it and its button out.
  final Widget? memberList;

  /// A title above [messages], such as the channel's name. In the collapsed
  /// layout it sits between the two buttons.
  final Widget? header;

  /// Whether the channel drawer is showing in the collapsed layout. Ignored
  /// when wide.
  final bool isChannelListOpen;

  /// Whether the member sheet is showing in the collapsed layout. Ignored
  /// when wide.
  final bool isMemberListOpen;

  /// Fires when the channel button or the scrim behind the drawer is tapped,
  /// with the caller expected to flip [isChannelListOpen]. Null disables the
  /// button.
  final VoidCallback? onToggleChannelList;

  /// Fires when the member button or the scrim behind the sheet is tapped,
  /// with the caller expected to flip [isMemberListOpen]. Null disables the
  /// button.
  final VoidCallback? onToggleMemberList;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final memberList = this.memberList;
    final header = this.header;
    final divider = VerticalDivider(
      width: QuarkSplitView.dividerWidth,
      color: tokens.border,
    );

    if (!QuarkSplitView.isCollapsed(context)) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A Material, not a ColoredBox: the lists' ListTiles paint their
          // ink on the nearest Material, which a ColoredBox would cover.
          Material(
            key: const ValueKey('chat_layout_channels'),
            color: tokens.sidebar,
            child: SizedBox(width: channelListWidth, child: channelList),
          ),
          divider,
          Expanded(
            child: Column(
              key: const ValueKey('chat_layout_messages'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (header != null) ...[
                  Padding(
                    padding: EdgeInsets.all(tokens.spacingMd),
                    child: header,
                  ),
                  Divider(height: 1, color: tokens.border),
                ],
                Expanded(child: messages),
              ],
            ),
          ),
          if (memberList != null) ...[
            divider,
            Material(
              key: const ValueKey('chat_layout_members'),
              color: tokens.sidebar,
              child: SizedBox(width: memberListWidth, child: memberList),
            ),
          ],
        ],
      );
    }

    final scrimColor = tokens.background.withValues(alpha: 0.7);
    final showMembers = isMemberListOpen && memberList != null;

    return Stack(
      children: [
        Column(
          key: const ValueKey('chat_layout_messages'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.all(tokens.spacingSm),
              child: Row(
                children: [
                  QuarkBarIconButton(
                    key: const ValueKey('chat_layout_channels_toggle'),
                    tooltip: 'Channels',
                    icon: QuarkIcons.menu,
                    onPressed: onToggleChannelList,
                  ),
                  SizedBox(width: tokens.spacingSm),
                  Expanded(child: header ?? const SizedBox.shrink()),
                  if (memberList != null) ...[
                    SizedBox(width: tokens.spacingSm),
                    QuarkBarIconButton(
                      key: const ValueKey('chat_layout_members_toggle'),
                      tooltip: 'Members',
                      icon: QuarkIcons.group_outlined,
                      onPressed: onToggleMemberList,
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: tokens.border),
            Expanded(child: messages),
          ],
        ),
        if (isChannelListOpen) ...[
          ModalBarrier(
            key: const ValueKey('chat_layout_scrim'),
            color: scrimColor,
            onDismiss: onToggleChannelList,
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: channelListWidth,
              height: double.infinity,
              child: Material(
                key: const ValueKey('chat_layout_channels'),
                color: tokens.sidebar,
                elevation: 8,
                child: SafeArea(right: false, child: channelList),
              ),
            ),
          ),
        ] else if (showMembers) ...[
          ModalBarrier(
            key: const ValueKey('chat_layout_scrim'),
            color: scrimColor,
            onDismiss: onToggleMemberList,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              widthFactor: 1,
              heightFactor: 0.6,
              child: Material(
                key: const ValueKey('chat_layout_members'),
                color: tokens.sidebar,
                elevation: 8,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(tokens.radiusLg),
                ),
                clipBehavior: Clip.antiAlias,
                child: SafeArea(top: false, child: memberList),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
