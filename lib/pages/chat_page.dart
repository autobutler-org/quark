import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/chat_channel_share_target.dart';
import 'package:quark/controllers/chat_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/chat_config.dart';
import 'package:quark/utils/clipboard_utils.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/chat/chat_channel_header.dart';
import 'package:quark/widgets/chat/chat_channel_not_found.dart';
import 'package:quark/widgets/chat/chat_failed_send_bar.dart';
import 'package:quark/widgets/chat/chat_unlock_prompt.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/sharing/show_share_sheet.dart';
import 'package:quark/widgets/users/user_avatar.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// Chat, a beta (#2421): the channels the account belongs to, the open
/// channel's messages and composer, and its members.
///
/// [channelId] comes from `/chat/:channelId`. `general` opens the default
/// channel, and the URL follows the channel actually open, so a reload or a
/// shared link lands on it. An id the account can't open says so in place of
/// the messages and keeps its URL (#2499). Picking a channel moves with
/// `context.go`.
///
/// The composer counts down near [ChatConfig.maxMessageLength] and won't
/// send past it (#2503).
///
/// While chat is locked, on web after a reload, the page asks for the
/// password before it shows anything else, saying why (#2494).
///
/// Above the composer, a notice says where the open channel's encryption
/// stands when it needs saying — waiting for the key, an unverified key, or
/// older messages that stay hidden — and what to do next (#2495). It, and
/// the "(?)" on each encryption line, explain encryption in a dialog
/// (#2496).
///
/// "New channel" creates a channel and goes to it. The channel header's
/// settings (#2422) edit the name and topic and delete, for holders of
/// `manage_channel` and admins, and open the members in the share sheet, for
/// holders of `manage_members` and admins, who also get add and remove in
/// the member list. Any member with a row of their own may leave, except in
/// `general`. An admin's channels they are not in are listed apart and open
/// without their messages. The author of a message, or a holder of
/// `delete_messages`, deletes it after confirming. A holder of `add_reactions`
/// reacts to a message, and taps a reaction of their own to take it back.
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
      // After the frame: selecting notifies, and a listener outside this
      // page, such as a closing dialog, can't be marked dirty mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.select(widget.channelId);
      });
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

  Future<void> _deleteMessage(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ConfirmDeleteDialog(
        title: 'Delete this message?',
        body:
            "It's removed for everyone in this channel. Deleting can't "
            'reach a copy someone already saved.',
        keyPrefix: 'delete_message',
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    );
    if (confirmed != true) return;
    final error = await _controller.deleteMessage(id);
    if (error == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(Errors.message(error, 'delete the message'))),
    );
  }

  Future<void> _explainEncryption() => showDialog<void>(
    context: context,
    builder: (dialogContext) => QuarkEncryptionHelpDialog(
      onClose: () => Navigator.of(dialogContext).pop(),
    ),
  );

  void _copyMessage(String id) {
    for (final message in _controller.messageItems) {
      if (message.id == id) copyToClipboard(context, message.body);
    }
  }

  Future<void> _react(String id, String emoji) async {
    final error = await _controller.toggleReaction(id, emoji);
    if (error == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(Errors.message(error, 'react to the message'))),
    );
  }

  void _openChannel(String id) {
    _controller.closeChannelList();
    context.go(AppRoutes.chatChannel(id));
  }

  String? _saveError(String action) {
    final error = _controller.saveError;
    return error == null ? null : Errors.chatChannel(error, action);
  }

  Future<void> _createChannel() async {
    _controller.clearSaveError();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: _controller,
        builder: (dialogContext, _) => QuarkChannelDialog(
          title: 'New channel',
          submitLabel: 'Create',
          nameMaxLength: ChatController.maxNameLength,
          topicMaxLength: ChatController.maxTopicLength,
          isSubmitting: _controller.isSaving,
          error: _saveError('create the channel'),
          onSubmit: (name, topic) async {
            final channel = await _controller.createChannel(name, topic);
            if (channel == null || !dialogContext.mounted) return;
            Navigator.of(dialogContext).pop();
            if (mounted) context.go(AppRoutes.chatChannel('${channel.id}'));
          },
          onCancel: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
  }

  Future<void> _editChannel() async {
    final channel = _controller.selectedChannel;
    if (channel == null) return;
    _controller.clearSaveError();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: _controller,
        builder: (dialogContext, _) => QuarkChannelDialog(
          title: 'Edit #${channel.name}',
          submitLabel: 'Save',
          initialName: channel.name,
          initialTopic: channel.topic,
          nameMaxLength: ChatController.maxNameLength,
          topicMaxLength: ChatController.maxTopicLength,
          isSubmitting: _controller.isSaving,
          error: _saveError('save the channel'),
          onSubmit: (name, topic) async {
            final saved = await _controller.updateChannel(name, topic);
            if (saved && dialogContext.mounted) {
              Navigator.of(dialogContext).pop();
            }
          },
          onCancel: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
  }

  Future<void> _openMembers() async {
    final channel = _controller.selectedChannel;
    if (channel == null) return;
    await showShareSheetFor(
      context,
      target: ChatChannelShareTarget(
        channel: channel,
        isAdmin: _controller.isAdmin,
        selfUserId: int.tryParse(_controller.currentUserKey ?? ''),
      ),
      name: '#${channel.name}',
    );
  }

  Future<void> _removeMember(String id) async {
    final member = _controller.memberItems.where((m) => m.id == id).firstOrNull;
    if (member == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ConfirmDeleteDialog(
        title: 'Remove ${member.name}?',
        body: _controller.memberReads(id)
            ? "The channel's key will change, so ${member.name} can't read "
                  'anything posted from now on. They keep whatever they '
                  'already downloaded.'
            : '${member.name} will no longer be able to manage this channel.',
        keyPrefix: 'remove_member',
        confirmLabel: 'Remove',
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    );
    if (confirmed != true) return;
    final error = await _controller.removeMember(id);
    if (error == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(Errors.message(error, 'remove them'))),
    );
  }

  Future<void> _deleteChannel() async {
    final channel = _controller.selectedChannel;
    if (channel == null) return;
    _controller.clearSaveError();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: _controller,
        builder: (dialogContext, _) => QuarkDeleteChannelDialog(
          channelName: channel.name,
          isSubmitting: _controller.isSaving,
          error: _saveError('delete the channel'),
          onConfirm: () async {
            final deleted = await _controller.deleteChannel();
            if (deleted && dialogContext.mounted) {
              Navigator.of(dialogContext).pop();
            }
          },
          onCancel: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
  }

  Future<void> _leaveChannel() async {
    final channel = _controller.selectedChannel;
    if (channel == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ConfirmDeleteDialog(
        title: 'Leave #${channel.name}?',
        body:
            "You'll stop seeing its messages. To come back, someone who "
            'manages its members has to add you again.',
        keyPrefix: 'leave_channel',
        confirmLabel: 'Leave',
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    );
    if (confirmed != true || await _controller.leaveChannel() || !mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          Errors.message(_controller.saveError, 'leave the channel'),
        ),
      ),
    );
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
        final encryption = c.encryptionStatus;
        return QuarkPageScaffold(
          title: 'Chat',
          icon: QuarkIcons.forum_outlined,
          actions: [
            QuarkBarChip(
              key: const ValueKey('chat_new_channel'),
              icon: QuarkIcons.add,
              label: 'New channel',
              onPressed: c.isLocked ? null : _createChannel,
            ),
            const AppThemeToggle(),
          ],
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
                          onEdit: c.canManageSelected ? _editChannel : null,
                          onMembers: c.canManageMembers ? _openMembers : null,
                          onDelete: c.canManageSelected && !channel.isDefault
                              ? _deleteChannel
                              : null,
                          onLeave: c.canLeaveSelected ? _leaveChannel : null,
                        ),
                  channelList: QuarkChannelList(
                    serverName: serverName,
                    channels: c.channelItems,
                    otherChannels: c.otherChannelItems,
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
                        child: c.isChannelMissing
                            ? ChatChannelNotFound(
                                onOpenGeneral: () => _openChannel(
                                  ChatController.defaultChannelSlug,
                                ),
                              )
                            : QuarkMessageList(
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
                                permissions: channel == null
                                    ? null
                                    : c.selectedPermissions,
                                currentUserId: c.currentUserKey,
                                onCopy: _copyMessage,
                                onDelete: _deleteMessage,
                                onReact: _react,
                                onEncryptionHelp: _explainEncryption,
                                onOpenLink: (uri) => launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                ),
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
                      if (encryption != null)
                        QuarkEncryptionNotice(
                          status: encryption,
                          isChecking: c.isCheckingKey,
                          onCheckAgain: c.checkKey,
                          onLearnMore: _explainEncryption,
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
                        permissions: channel == null
                            ? null
                            : c.selectedPermissions,
                        isWaitingForKey: c.isWaitingForKey,
                        disabledReason: c.composerDisabledReason,
                        maxLength: ChatConfig.maxMessageLength,
                        onSend: c.send,
                      ),
                    ],
                  ),
                  memberList: QuarkMemberList(
                    members: c.memberItems,
                    permissions: c.managingPermissions,
                    onAddMembers: _openMembers,
                    onRemove: _removeMember,
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
