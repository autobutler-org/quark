import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../layout/quark_bar_icon_button.dart';
import '../layout/quark_resizable_pane.dart';
import '../layout/quark_sheet.dart';
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
/// fired by the buttons beside [header] and by a tap on the scrim. The member
/// sheet is a [QuarkSheet] with a close button that fires
/// [onToggleMemberList] too, and system back closes an open drawer or sheet
/// through the same callbacks rather than leaving the page (#2585). A caller
/// closes the drawer itself when a channel is picked from it. Nothing slides:
/// the drawer and the sheet appear in place, so there is no motion to reduce.
///
/// In the wide layout each side pane is a [QuarkResizablePane]: drag its
/// inner edge to resize it, or below its min width to collapse it (#4294).
/// Their widths and collapsed flags are the caller's as well:
/// [channelPaneWidth] and [isChannelPaneCollapsed] in,
/// [onChannelPaneWidthChanged] and [onChannelPaneCollapsedChanged] out, and
/// the same four for the member pane. A collapsed pane disappears entirely,
/// with no rail; the buttons beside [header], which the wide layout shows
/// once a collapse callback is supplied, hide and reopen it. Each pane may
/// take a quarter of the window, so the messages always keep half.
///
/// Key prefixes: `chat_layout_channels`, `chat_layout_messages` and
/// `chat_layout_members` on the three panes, `chat_layout_channels_toggle`
/// and `chat_layout_members_toggle` on the buttons beside [header],
/// [QuarkResizablePane]'s keys with the ids `chat_channels` and
/// `chat_members` on the wide layout's panes and handles,
/// `chat_layout_scrim` behind an open drawer or sheet, and [QuarkSheet]'s
/// `quark_sheet_close` on the member sheet's close button.
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
    this.channelPaneWidth = channelListWidth,
    this.isChannelPaneCollapsed = false,
    this.onChannelPaneWidthChanged,
    this.onChannelPaneCollapsedChanged,
    this.memberPaneWidth = memberListWidth,
    this.isMemberPaneCollapsed = false,
    this.onMemberPaneWidthChanged,
    this.onMemberPaneCollapsedChanged,
    super.key,
  });

  /// The default width of the channel pane in the wide layout, and the
  /// width of the drawer in the collapsed one.
  static const double channelListWidth = QuarkSplitView.defaultSidebarWidth;

  /// The default width of the member pane in the wide layout.
  static const double memberListWidth = 240;

  /// The share of the window each side pane may take, so the two together
  /// leave the messages at least half.
  static const double paneMaxFraction = 0.25;

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

  /// The channel pane's width in the wide layout. Ignored when collapsed to
  /// a drawer, which is always [channelListWidth].
  final double channelPaneWidth;

  /// Whether the channel pane is hidden in the wide layout. Ignored when
  /// narrow.
  final bool isChannelPaneCollapsed;

  /// Fires with the channel pane's new width as its handle is dragged. Null
  /// keeps the pane at [channelPaneWidth].
  final ValueChanged<double>? onChannelPaneWidthChanged;

  /// Fires when the channel pane is collapsed or reopened in the wide
  /// layout, by its handle or the button beside [header]. Null leaves the
  /// button out and keeps the pane open.
  final ValueChanged<bool>? onChannelPaneCollapsedChanged;

  /// The member pane's width in the wide layout.
  final double memberPaneWidth;

  /// Whether the member pane is hidden in the wide layout. Ignored when
  /// narrow.
  final bool isMemberPaneCollapsed;

  /// Fires with the member pane's new width as its handle is dragged. Null
  /// keeps the pane at [memberPaneWidth].
  final ValueChanged<double>? onMemberPaneWidthChanged;

  /// Fires when the member pane is collapsed or reopened in the wide layout,
  /// by its handle or the button beside [header]. Null leaves the button out
  /// and keeps the pane open.
  final ValueChanged<bool>? onMemberPaneCollapsedChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final memberList = this.memberList;
    final header = this.header;
    final wide = !QuarkSplitView.isCollapsed(context);
    final onChannelPaneCollapsedChanged = this.onChannelPaneCollapsedChanged;
    final onMemberPaneCollapsedChanged = this.onMemberPaneCollapsedChanged;
    // The narrow layout always has its buttons; the wide one only once the
    // caller lets the panes collapse.
    final channelButton = !wide
        ? (tooltip: 'Channels', onPressed: onToggleChannelList)
        : onChannelPaneCollapsedChanged == null
        ? null
        : (
            tooltip: isChannelPaneCollapsed ? 'Show channels' : 'Hide channels',
            onPressed: () =>
                onChannelPaneCollapsedChanged(!isChannelPaneCollapsed),
          );
    final memberButton = memberList == null
        ? null
        : !wide
        ? (tooltip: 'Members', onPressed: onToggleMemberList)
        : onMemberPaneCollapsedChanged == null
        ? null
        : (
            tooltip: isMemberPaneCollapsed ? 'Show members' : 'Hide members',
            onPressed: () =>
                onMemberPaneCollapsedChanged(!isMemberPaneCollapsed),
          );
    final headerBar = channelButton == null && memberButton == null
        ? (header == null
              ? null
              : Padding(
                  padding: EdgeInsets.all(tokens.spacingMd),
                  child: header,
                ))
        : Padding(
            // Less the margin around each button's 48dp touch target
            // (#2605), so the header stands as tall as it did and the
            // buttons' visible edges sit where they did.
            padding: EdgeInsets.all(
              tokens.spacingSm - QuarkBarIconButton.tapTargetMargin,
            ),
            child: Row(
              children: [
                if (channelButton != null) ...[
                  QuarkBarIconButton(
                    key: const ValueKey('chat_layout_channels_toggle'),
                    tooltip: channelButton.tooltip,
                    icon: QuarkIcons.menu,
                    onPressed: channelButton.onPressed,
                  ),
                  SizedBox(width: tokens.spacingSm),
                ],
                Expanded(child: header ?? const SizedBox.shrink()),
                if (memberButton != null) ...[
                  SizedBox(width: tokens.spacingSm),
                  QuarkBarIconButton(
                    key: const ValueKey('chat_layout_members_toggle'),
                    tooltip: memberButton.tooltip,
                    icon: QuarkIcons.group_outlined,
                    onPressed: memberButton.onPressed,
                  ),
                ],
              ],
            ),
          );
    final messagePane = Column(
      key: const ValueKey('chat_layout_messages'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (headerBar != null) ...[
          headerBar,
          Divider(height: 1, color: tokens.border),
        ],
        Expanded(child: messages),
      ],
    );

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QuarkResizablePane(
            id: 'chat_channels',
            semanticLabel: 'Resize channels',
            width: channelPaneWidth,
            defaultWidth: channelListWidth,
            isCollapsed: isChannelPaneCollapsed,
            maxFraction: paneMaxFraction,
            onWidthChanged: onChannelPaneWidthChanged,
            onCollapsedChanged: onChannelPaneCollapsedChanged,
            // A Material, not a ColoredBox: the lists' ListTiles paint their
            // ink on the nearest Material, which a ColoredBox would cover.
            child: Material(
              key: const ValueKey('chat_layout_channels'),
              color: tokens.sidebar,
              child: channelList,
            ),
          ),
          Expanded(child: messagePane),
          if (memberList != null)
            QuarkResizablePane(
              id: 'chat_members',
              semanticLabel: 'Resize members',
              edge: QuarkPaneEdge.end,
              width: memberPaneWidth,
              defaultWidth: memberListWidth,
              isCollapsed: isMemberPaneCollapsed,
              maxFraction: paneMaxFraction,
              onWidthChanged: onMemberPaneWidthChanged,
              onCollapsedChanged: onMemberPaneCollapsedChanged,
              child: Material(
                key: const ValueKey('chat_layout_members'),
                color: tokens.sidebar,
                child: memberList,
              ),
            ),
        ],
      );
    }

    final scrimColor = tokens.background.withValues(alpha: 0.7);
    final showMembers = isMemberListOpen && memberList != null;

    final closeOverlay = isChannelListOpen
        ? onToggleChannelList
        : showMembers
        ? onToggleMemberList
        : null;

    // Back closes the drawer or the sheet before it leaves the page.
    return PopScope(
      canPop: closeOverlay == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) closeOverlay?.call();
      },
      child: Stack(
        children: [
          messagePane,
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
              child: Material(
                key: const ValueKey('chat_layout_members'),
                color: tokens.sidebar,
                elevation: 8,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(tokens.radiusLg),
                ),
                clipBehavior: Clip.antiAlias,
                child: QuarkSheet(
                  title: 'Members',
                  onClose: onToggleMemberList ?? () {},
                  scrollable: false,
                  child: memberList,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
