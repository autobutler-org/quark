import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/chat_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/chat/chat_channel_header.dart';
import 'package:quark/widgets/chat/chat_failed_send_bar.dart';
import 'package:quark/widgets/chat/chat_unlock_prompt.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/users/user_avatar.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Chat, a beta (#2421): the channels the account belongs to, the open
/// channel's messages and composer, and its members.
///
/// [channelId] comes from `/chat/:channelId`. An id the account can't open,
/// and `general`, open the default channel, and the URL follows the channel
/// actually open, so a reload or a shared link lands on it. Picking a channel
/// moves with `context.go`.
///
/// While chat is locked, on web after a reload, the page asks for the
/// password before it shows anything else.
class ChatPage extends StatefulWidget {
  /// Creates the page on channel [channelId].
  const ChatPage({required this.channelId, this.controller, super.key});

  /// The channel in the URL: an id, or `general`.
  final String channelId;

  /// A controller to use instead of the real one; the page disposes it.
  @visibleForTesting
  final ChatController? controller;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  late final ChatController _controller =
      (widget.controller ?? ChatController())..select(widget.channelId);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_followController);
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.channelId != oldWidget.channelId) {
      _controller.select(widget.channelId);
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_followController)
      ..dispose();
    super.dispose();
  }

  @override
  Future<void> refresh() => _controller.refresh();

  /// Puts the URL on the channel actually open, when the one asked for fell
  /// back to the default. After the frame: this can run from
  /// [didUpdateWidget], mid-build.
  void _followController() {
    final id = _controller.selectedChannel?.id;
    if (id == null || '$id' == widget.channelId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && '$id' != widget.channelId) {
        context.go(AppRoutes.chatChannel('$id'));
      }
    });
  }

  void _openChannel(String id) {
    _controller.closeChannelList();
    context.go(AppRoutes.chatChannel(id));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        final channel = c.selectedChannel;
        final settings = AppSettings.instance;
        final hostIndex = settings.activeIndex;
        final serverName = hostIndex >= 0 && hostIndex < settings.hosts.length
            ? settings.hosts[hostIndex].name
            : 'Quark';
        final failed = c.failedSends.firstOrNull;
        final messagesError = channel == null
            ? c.channelsError
            : c.messagesError;
        return QuarkPageScaffold(
          title: 'Chat',
          icon: QuarkIcons.forum_outlined,
          actions: const [AppThemeToggle()],
          onRefresh: manualRefresh,
          isRefreshing: isRefreshing,
          drawer: const AppDrawer(activeSection: QuarkDrawerSection.chat),
          body: c.isLocked
              ? ChatUnlockPrompt(
                  onUnlock: c.unlock,
                  isBusy: c.isUnlocking,
                  error: c.unlockError == null
                      ? null
                      : Errors.message(c.unlockError, 'unlock your messages'),
                )
              : QuarkChatLayout(
                  header: channel == null
                      ? null
                      : ChatChannelHeader(
                          name: channel.name,
                          topic: channel.topic,
                        ),
                  channelList: QuarkChannelList(
                    serverName: serverName,
                    channels: c.channelItems,
                    selectedChannelId: channel == null ? null : '${channel.id}',
                    isLoading: c.isLoadingChannels && c.channels.isEmpty,
                    error: c.channelsError == null
                        ? null
                        : Errors.message(c.channelsError, 'load the channels'),
                    onSelect: _openChannel,
                  ),
                  messages: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: QuarkMessageList(
                          messages: c.messageItems,
                          isLoading:
                              c.isLoadingMessages ||
                              (channel == null && c.isLoadingChannels),
                          error: messagesError == null
                              ? null
                              : Errors.message(
                                  messagesError,
                                  'load the channel',
                                ),
                          hasMore: c.hasOlderMessages,
                          onLoadOlder: c.loadOlder,
                          avatarBuilder: (context, userId) {
                            final id = int.tryParse(userId) ?? 0;
                            return UserAvatar(
                              userId: id,
                              name: c.nameOf(id),
                              version: c.avatarVersionOf(id),
                              size: QuarkMessageList.avatarSize,
                            );
                          },
                        ),
                      ),
                      if (failed != null)
                        ChatFailedSendBar(
                          text: failed.text,
                          error: Errors.message(
                            failed.error,
                            'send the message',
                          ),
                          onRetry: () => c.retry(failed.id),
                          onDiscard: () => c.discard(failed.id),
                        ),
                      QuarkMessageComposer(
                        // A draft belongs to its channel.
                        key: ValueKey('chat_composer_${channel?.id}'),
                        hintText: channel == null
                            ? 'Message'
                            : 'Message #${channel.name}',
                        disabledReason: c.composerDisabledReason,
                        onSend: c.send,
                      ),
                    ],
                  ),
                  memberList: QuarkMemberList(
                    members: c.memberItems,
                    expandedIds: c.expandedGroupIds,
                    onToggleExpanded: c.toggleGroup,
                    isLoading: c.isLoadingMembers && c.members.isEmpty,
                    error: c.membersError == null
                        ? null
                        : Errors.message(c.membersError, 'load the members'),
                    avatarBuilder: (context, userId) {
                      final id = int.tryParse(userId) ?? 0;
                      return UserAvatar(
                        userId: id,
                        name: c.nameOf(id),
                        version: c.avatarVersionOf(id),
                        size: QuarkMemberList.avatarSize,
                      );
                    },
                  ),
                  isChannelListOpen: c.isChannelListOpen,
                  isMemberListOpen: c.isMemberListOpen,
                  onToggleChannelList: c.toggleChannelList,
                  onToggleMemberList: c.toggleMemberList,
                ),
        );
      },
    );
  }
}
