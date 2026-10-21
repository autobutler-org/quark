import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/chat_channel_share_target.dart';
import 'package:quark/controllers/chat_controller.dart';
import 'package:quark/controllers/chat_unread_controller.dart';
import 'package:quark/controllers/recovery_phrase_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/chat_config.dart';
import 'package:quark/utils/clipboard_utils.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/widgets/chat/chat_channel_header.dart';
import 'package:quark/widgets/chat/chat_channel_not_found.dart';
import 'package:quark/widgets/chat/chat_failed_send_bar.dart';
import 'package:quark/widgets/chat/chat_search_bar.dart';
import 'package:quark/widgets/chat/chat_unlock_prompt.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/recovery_phrase/add_recovery_phrase_offer.dart';
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
/// While chat is locked, in a new browser tab, the page asks for the
/// password before it shows anything else, saying why (#2494).
///
/// Above the composer, a notice says where the open channel's encryption
/// stands when it needs saying — waiting for the key, an unverified key, or
/// older messages that stay hidden — and what to do next (#2495). It, and
/// the "(?)" on each encryption line, explain encryption in a dialog
/// (#2496).
///
/// "New channel" creates a channel and goes to it, asking whether it is
/// private or open to every account and saying what each means (#2501).
/// "Message someone" picks an account and goes to a private channel with
/// them, made the first time (#2497). A private channel's header carries a
/// lock that says the same. The channel header's settings (#2422), with
/// leave and delete set apart below a divider (#2498), edit the name and
/// topic and delete, for holders of
/// `manage_channel` and admins, and open the members in the share sheet, for
/// holders of `manage_members` and admins, who also get add and remove in
/// the member list. Any member with a row of their own may leave, except in
/// `general`. An admin's channels they are not in are listed apart and open
/// without their messages. The author of a message, or a holder of
/// `delete_messages`, deletes it after confirming. A holder of `add_reactions`
/// reacts to a message, and taps a reaction of their own to take it back.
///
/// Typing `@` in the composer suggests the open channel's members, and a
/// message that mentions the signed-in account is highlighted (#2623). A
/// mention is the text `@name` inside the encrypted message, found on this
/// device; the Quark is never told who was mentioned.
///
/// The header's search (#2429) opens a bar above the messages and narrows
/// them to the ones containing what is typed. Chat is end-to-end encrypted,
/// so it runs on this device over the messages already loaded and decrypted;
/// the bar says so, counts the matches, and loads older messages to reach
/// further back. Nothing typed there goes to the Quark.
class ChatPage extends StatefulWidget {
  /// Creates the page on channel [channelId].
  const ChatPage({
    required this.channelId,
    this.controller,
    this.recoveryPhrase,
    super.key,
  });

  /// The channel in the URL: an id, or `general`.
  final String channelId;

  /// A controller to use instead of the real one; the page disposes it.
  @visibleForTesting
  final ChatController? controller;

  /// The offer to add the recovery phrase to chat keys that have no wrap
  /// under it (#3530); the app's by default.
  @visibleForTesting
  final RecoveryPhraseController? recoveryPhrase;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  late final ChatController _controller =
      (widget.controller ?? ChatController())..select(widget.channelId);
  late final RecoveryPhraseController _phrase =
      widget.recoveryPhrase ?? RecoveryPhraseController.instance;

  /// Whether this window is focused on the page. An unfocused window keeps
  /// the open channel's unread badge; a focused one does not (#3255).
  bool _windowFocused = true;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _windowFocused =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _controller.addListener(_followController);
    _syncViewing();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final focused = state == AppLifecycleState.resumed;
    if (focused == _windowFocused) return;
    setState(() => _windowFocused = focused);
    _syncViewing();
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
    ChatUnreadController.instance.setViewing(null, focused: false);
    super.dispose();
  }

  @override
  Future<void> refresh() =>
      Future.wait([_controller.refresh(), _phrase.check()]);

  /// Puts the URL on the channel actually open, when the one asked for fell
  /// back to the default. After the frame: this can run from
  /// [didUpdateWidget], mid-build.
  void _followController() {
    _syncViewing();
    final id = _controller.selectedChannel?.id;
    if (id == null || '$id' == widget.channelId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && '$id' != widget.channelId) {
        context.go(AppRoutes.chatChannel('$id'));
      }
    });
  }

  Future<void> _deleteMessage(String id) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete this message?',
      body:
          "It's removed for everyone in this channel. Deleting can't "
          'reach a copy someone already saved.',
      keyPrefix: 'delete_message',
    );
    if (!confirmed) return;
    final error = await _controller.deleteMessage(id);
    if (error == null || !mounted) return;
    showMessage(context, Errors.message(error, 'delete the message'));
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
    showMessage(context, Errors.message(error, 'react to the message'));
  }

  void _openChannel(String id) {
    _controller.closeChannelList();
    context.go(AppRoutes.chatChannel(id));
  }

  /// Tells the shared unread counts which channel is on screen, so its badge
  /// stays at zero while this window is focused on it.
  void _syncViewing() {
    final id = _windowFocused ? _controller.selectedChannel?.id : null;
    ChatUnreadController.instance.setViewing(id, focused: id != null);
  }

  /// The channel list with the open channel's own badges removed while this
  /// window is focused on it. [openId] is null when the badge should show.
  List<ChatChannelItem> _channelsWithoutOwnBadge(
    List<ChatChannelItem> items,
    String? openId,
  ) {
    if (openId == null) return items;
    return [
      for (final item in items)
        if (item.id == openId)
          ChatChannelItem(
            id: item.id,
            name: item.name,
            isPrivate: item.isPrivate,
            permissions: item.permissions,
          )
        else
          item,
    ];
  }

  String? _saveError(String action) {
    final error = _controller.saveError;
    return error == null ? null : Errors.chatChannel(error, action);
  }

  Future<void> _createChannel() async {
    _controller.clearSaveError();
    // Not disposed: the dialog still rebuilds from it while it animates out
    // after showDialog returns, and once it's gone nothing listens.
    final isPrivate = ValueNotifier(true);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: Listenable.merge([_controller, isPrivate]),
        builder: (dialogContext, _) => QuarkChannelDialog(
          title: 'New channel',
          submitLabel: 'Create',
          nameMaxLength: ChatController.maxNameLength,
          topicMaxLength: ChatController.maxTopicLength,
          isSubmitting: _controller.isSaving,
          error: _saveError('create the channel'),
          isPrivate: isPrivate.value,
          onPrivacyChanged: (value) => isPrivate.value = value,
          onSubmit: (name, topic) async {
            final channel = await _controller.createChannel(
              name,
              topic,
              isPrivate: isPrivate.value,
            );
            if (channel == null || !dialogContext.mounted) return;
            Navigator.of(dialogContext).pop();
            _goToCreated(channel.id, 'open the channel to everyone');
          },
          onCancel: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
  }

  Future<void> _messageSomeone() async {
    _controller.clearSaveError();
    unawaited(_controller.loadPeople());
    // Not disposed, for the same reason as in _createChannel.
    final picked = ValueNotifier<PrincipalItem?>(null);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: Listenable.merge([_controller, picked]),
        builder: (dialogContext, _) => QuarkStartConversationDialog(
          people: _controller.people,
          selected: picked.value,
          isLoading: _controller.isLoadingPeople,
          loadError: _controller.peopleError == null
              ? null
              : Errors.message(_controller.peopleError, 'load the people'),
          isSubmitting: _controller.isSaving,
          error: _saveError('start the conversation'),
          onSelected: (person) => picked.value = person,
          onStart: () async {
            final person = picked.value;
            if (person == null) return;
            final channel = await _controller.startConversation(person.id);
            if (channel == null || !dialogContext.mounted) return;
            Navigator.of(dialogContext).pop();
            _goToCreated(channel.id, 'add ${person.name}');
          },
          onCancel: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
  }

  /// Goes to channel [id] just made, saying so when the step after making it,
  /// [action], failed.
  void _goToCreated(int id, String action) {
    if (!mounted) return;
    final error = _controller.saveError;
    if (error != null) {
      showMessage(context, Errors.message(error, action));
    }
    context.go(AppRoutes.chatChannel('$id'));
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
      name: _controller.titleOf(channel),
    );
  }

  Future<void> _removeMember(String id) async {
    final member = _controller.memberItems.where((m) => m.id == id).firstOrNull;
    if (member == null) return;
    final confirmed = await confirmDestructive(
      context,
      title: 'Remove ${member.name}?',
      body: _controller.memberReads(id)
          ? "The channel's key will change, so ${member.name} can't read "
                'anything posted from now on. They keep whatever they '
                'already downloaded.'
          : '${member.name} will no longer be able to manage this channel.',
      keyPrefix: 'remove_member',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    final error = await _controller.removeMember(id);
    if (error == null || !mounted) return;
    showMessage(context, Errors.message(error, 'remove them'));
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
    final confirmed = await confirmDestructive(
      context,
      title: 'Leave ${_controller.titleOf(channel)}?',
      body:
          "You'll stop seeing its messages. To come back, someone who "
          'manages its members has to add you again.',
      keyPrefix: 'leave_channel',
      confirmLabel: 'Leave',
    );
    if (!confirmed || await _controller.leaveChannel() || !mounted) {
      return;
    }
    showMessage(
      context,
      Errors.message(_controller.saveError, 'leave the channel'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, _phrase]),
      builder: (context, _) {
        final c = _controller;
        final channel = c.selectedChannel;
        final settings = AppSettings.instance;
        final hostIndex = settings.activeIndex;
        final serverName = hostIndex >= 0 && hostIndex < settings.hosts.length
            ? settings.hosts[hostIndex].name
            : 'Quark';
        final messagesError = channel == null
            ? c.channelsError
            : c.messagesError;
        final encryption = c.encryptionStatus;
        final matches = c.searchMatchCount;
        final openId = _windowFocused && channel != null
            ? '${channel.id}'
            : null;
        final partner = channel == null ? null : c.directPartnerOf(channel);
        return QuarkPageScaffold(
          title: 'Chat',
          icon: QuarkIcons.forum_outlined,
          actions: [
            QuarkBarChip(
              key: const ValueKey('chat_message_someone'),
              icon: QuarkIcons.person_add_outlined,
              label: 'Message someone',
              tooltip: 'Start a private channel with one person',
              onPressed: c.isLocked ? null : _messageSomeone,
            ),
            QuarkBarChip(
              key: const ValueKey('chat_new_channel'),
              icon: QuarkIcons.add,
              label: 'New channel',
              tooltip: 'Create a channel, private or for everyone',
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
              : Column(
                  children: [
                    if (_phrase.offerChat)
                      AddRecoveryPhraseOffer(controller: _phrase),
                    Expanded(
                      child: QuarkChatLayout(
                        header: channel == null
                            ? null
                            : ChatChannelHeader(
                                name: partner ?? channel.name,
                                isDirect: partner != null,
                                topic: channel.topic,
                                isPrivate: channel.isPrivate,
                                onSearch: c.canSearch ? c.toggleSearch : null,
                                onEdit: c.canManageSelected
                                    ? _editChannel
                                    : null,
                                onMembers: c.canManageMembers
                                    ? _openMembers
                                    : null,
                                onDelete:
                                    c.canManageSelected && !channel.isDefault
                                    ? _deleteChannel
                                    : null,
                                onLeave: c.canLeaveSelected
                                    ? _leaveChannel
                                    : null,
                              ),
                        channelList: QuarkChannelList(
                          serverName: serverName,
                          channels: _channelsWithoutOwnBadge(
                            c.channelItems,
                            openId,
                          ),
                          otherChannels: _channelsWithoutOwnBadge(
                            c.otherChannelItems,
                            openId,
                          ),
                          selectedChannelId: channel == null
                              ? null
                              : '${channel.id}',
                          isLoading: c.isLoadingChannels && c.channels.isEmpty,
                          error: c.channelsError == null
                              ? null
                              : Errors.message(
                                  c.channelsError,
                                  'load the channels',
                                ),
                          onSelect: _openChannel,
                        ),
                        messages: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (c.isSearching)
                              ChatSearchBar(
                                matchCount: matches,
                                hasOlder: c.hasOlderMessages,
                                isLoadingOlder: c.isLoadingMessages,
                                onChanged: c.search,
                                onLoadOlder: c.loadOlder,
                                onClose: c.toggleSearch,
                              ),
                            Expanded(
                              child: c.isChannelMissing
                                  ? ChatChannelNotFound(
                                      onOpenGeneral: () => _openChannel(
                                        ChatController.defaultChannelSlug,
                                      ),
                                    )
                                  : matches == 0
                                  ? const EmptyStateWidget(
                                      icon: QuarkIcons.search,
                                      headline: 'No loaded message matches',
                                      subtext:
                                          'Only the messages loaded on this device '
                                          'are searched.',
                                    )
                                  : QuarkMessageList(
                                      key: ValueKey(
                                        'chat_messages_${channel?.id ?? 'none'}',
                                      ),
                                      messages: c.messageItems,
                                      isLoading:
                                          c.isLoadingMessages ||
                                          (channel == null &&
                                              c.isLoadingChannels),
                                      error: messagesError == null
                                          ? null
                                          : Errors.message(
                                              messagesError,
                                              'load the channel',
                                            ),
                                      // While searching, the search bar offers
                                      // older messages instead.
                                      hasMore:
                                          matches == null && c.hasOlderMessages,
                                      onLoadOlder: c.loadOlder,
                                      onAtBottomChanged: c.setAtBottom,
                                      permissions: channel == null
                                          ? null
                                          : c.selectedPermissions,
                                      currentUserId: c.currentUserKey,
                                      mentionNames: c.mentionNames,
                                      currentUserName: c.currentUserName,
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
                            for (final send in c.outboundSends)
                              ChatFailedSendBar(
                                id: send.id,
                                text: send.text,
                                error: send.failed
                                    ? Errors.message(
                                        send.error,
                                        'send the message',
                                      )
                                    : null,
                                onRetry: () => c.retry(send.id),
                                onDiscard: () => c.discard(send.id),
                              ),
                            // Chrome pinned to the bottom edge keeps clear of the
                            // rounded display corners and the home indicator
                            // (#2788).
                            QuarkEdgeInset(
                              child: QuarkMessageComposer(
                                // A new state per channel. The text is that
                                // channel's draft, kept for this app session.
                                key: ValueKey('chat_composer_${channel?.id}'),
                                initialText: channel == null
                                    ? ''
                                    : c.draftFor(channel.id),
                                onChanged: channel == null
                                    ? null
                                    : (text) => c.setDraft(channel.id, text),
                                hintText: channel == null
                                    ? 'Message'
                                    : 'Message ${c.titleOf(channel)}',
                                permissions: channel == null
                                    ? null
                                    : c.selectedPermissions,
                                isWaitingForKey: c.isWaitingForKey,
                                disabledReason: c.composerDisabledReason,
                                maxLength: ChatConfig.maxMessageLength,
                                mentionNames: c.mentionNames,
                                onSend: c.send,
                              ),
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
                              : Errors.message(
                                  c.membersError,
                                  'load the members',
                                ),
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
                    ),
                  ],
                ),
        );
      },
    );
  }
}
