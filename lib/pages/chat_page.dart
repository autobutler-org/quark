import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/chat_channel_share_target.dart';
import 'package:quark/controllers/chat_controller.dart';
import 'package:quark/controllers/chat_messages_controller.dart';
import 'package:quark/controllers/chat_unread_controller.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/chat_attachment_playback.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/chat_config.dart';
import 'package:quark/utils/clipboard_utils.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark/widgets/chat/chat_attachment_preview.dart';
import 'package:quark/widgets/chat/chat_channel_header.dart';
import 'package:quark/widgets/chat/chat_channel_not_found.dart';
import 'package:quark/widgets/chat/chat_failed_send_bar.dart';
import 'package:quark/widgets/chat/chat_search_bar.dart';
import 'package:quark/widgets/chat/chat_unlock_prompt.dart';
import 'package:quark/widgets/chat/native_emoji_dialog.dart';
import 'package:quark/widgets/chat/show_chat_poll_editor.dart';
import 'package:quark/widgets/chat/show_chat_poll_export.dart';
import 'package:quark/widgets/chat/show_chat_save_folder.dart';
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
/// The attach button on the composer sends one file from this device. The
/// caption is whatever is in the field, and it may be empty. A photo opens
/// in the image viewer. A video is decrypted to a temporary file and played.
/// Saving an attachment decrypts it on this device. A picture or video on a
/// phone goes to the photo library, and anything else through the save
/// dialog. Saving to my files asks for a folder and uploads the plaintext
/// there under the file's name, beside a file that already has that name.
///
/// The poll button beside the composer opens a form for a poll (#3894). A
/// holder of `add_reactions` answers one, and its author closes it. Each
/// card is tallied on this device from the answers it can open. Anyone who
/// can see a poll's results exports them as CSV, JSON or a sheet, downloaded
/// or saved to their home folder on the Quark.
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

  /// Whether this window is focused on the page. An unfocused window keeps
  /// the open channel's unread badge; a focused one does not (#3255).
  bool _windowFocused = true;

  /// Bumped after an attachment send so the composer remounts empty. The
  /// field does not follow [ChatController.draftFor] after it is created.
  int _composerEpoch = 0;

  /// Whether a file pick and upload is already running.
  bool _attaching = false;

  /// Whether an attachment save is already running.
  bool _savingAttachment = false;

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
  Future<void> refresh() => _controller.refresh();

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

  Future<void> _regenerateKey() async {
    final confirmed = await confirmDestructive(
      context,
      title: "Regenerate this channel's keys?",
      body:
          'Members who have set up chat get a new key now, so this channel '
          'can be used again. ${QuarkEncryptionNotice.regenerateHint}',
      keyPrefix: 'regenerate_keys',
      confirmLabel: 'Regenerate',
      destructive: false,
    );
    if (!confirmed || !mounted) return;
    final error = await _controller.regenerateKey();
    if (error == null || !mounted) return;
    showMessage(context, Errors.message(error, 'regenerate the channel keys'));
  }

  Future<void> _explainEncryption() => showDialog<void>(
    context: context,
    builder: (dialogContext) => QuarkEncryptionHelpDialog(
      onClose: () => Navigator.of(dialogContext).pop(),
    ),
  );

  Future<void> _attachFile() async {
    if (_attaching) return;
    final channel = _controller.selectedChannel;
    if (channel == null) return;
    _attaching = true;
    try {
      final file = await FilePicker.pickFile();
      if (!mounted || file == null) return;
      final bytes = await file.readAsBytes();
      final name = file.name.trim().isEmpty ? 'file' : file.name.trim();
      final caption = _controller.draftFor(channel.id).trim();
      final error = await _controller.sendAttachment(
        name: name,
        mime: _chatFileMime(name),
        bytes: bytes,
        caption: caption,
      );
      if (!mounted) return;
      if (error != null) {
        showMessage(context, Errors.message(error, 'send the file'));
        return;
      }
      _controller.setDraft(channel.id, '');
      setState(() => _composerEpoch++);
    } finally {
      _attaching = false;
    }
  }

  Future<void> _openAttachment(ChatAttachmentItem item) async {
    if (item.kind != ChatAttachmentKind.image) return;
    try {
      final bytes = await _controller.readAttachmentImage(item.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ImageViewerPage(bytes: bytes, name: item.name),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showMessage(context, Errors.message(e, 'open the image'));
    }
  }

  Future<void> _saveAttachmentToDevice(ChatAttachmentItem item) async {
    if (_savingAttachment) return;
    _savingAttachment = true;
    try {
      final saved = await _controller.saveAttachmentToDevice(item.id);
      if (saved == null || !mounted) return;
      showMessage(context, 'Saved');
    } catch (error) {
      if (!mounted) return;
      showMessage(context, Errors.message(error, 'save the file'));
    } finally {
      _savingAttachment = false;
    }
  }

  Future<void> _saveAttachmentToFiles(ChatAttachmentItem item) async {
    if (_savingAttachment) return;
    _savingAttachment = true;
    try {
      final folder = await showChatSaveFolderPicker(context);
      if (folder == null || !mounted) return;
      await _controller.saveAttachmentToFolder(item.id, folder);
      if (!mounted) return;
      showMessage(context, 'Saved to my files');
    } catch (error) {
      if (!mounted) return;
      showMessage(context, Errors.message(error, 'save the file'));
    } finally {
      _savingAttachment = false;
    }
  }

  Future<void> _playAttachment(ChatAttachmentItem item) async {
    if (!chatVideoPlaybackSupported) {
      showMessage(
        context,
        Errors.message(UnsupportedError('no local file'), 'play the video'),
      );
      return;
    }
    try {
      await playChatAttachmentVideo(
        context: context,
        name: item.name,
        mime: item.mime,
        plaintext: _controller.openAttachmentPlaintext(item.id),
      );
    } catch (e) {
      if (!mounted) return;
      showMessage(context, Errors.message(e, 'play the video'));
    }
  }

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

  Future<void> _answerPoll(String id, ChatPollAnswer answer) async {
    final error = await _controller.answerPoll(id, answer);
    if (error == null || !mounted) return;
    showMessage(context, Errors.message(error, 'answer the poll'));
  }

  Future<void> _closePoll(String id) async {
    final error = await _controller.closePoll(id);
    if (error == null || !mounted) return;
    showMessage(context, Errors.message(error, 'close the poll'));
  }

  Future<void> _exportPoll(String id) async {
    final choice = await showChatPollExport(context);
    if (choice == null) return;
    final (format, destination) = choice;
    try {
      final saved = await _controller.exportPoll(id, format, destination);
      if (saved != null && mounted) showMessage(context, 'Exported to $saved');
    } catch (e) {
      if (!mounted) return;
      showMessage(context, Errors.message(e, 'export the results'));
    }
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
      listenable: _controller,
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
              : QuarkChatLayout(
                  header: channel == null
                      ? null
                      : ChatChannelHeader(
                          name: partner ?? channel.name,
                          isDirect: partner != null,
                          topic: channel.topic,
                          isPrivate: channel.isPrivate,
                          onSearch: c.canSearch ? c.toggleSearch : null,
                          onEdit: c.canManageSelected ? _editChannel : null,
                          onMembers: c.canManageMembers ? _openMembers : null,
                          onDelete: c.canManageSelected && !channel.isDefault
                              ? _deleteChannel
                              : null,
                          onLeave: c.canLeaveSelected ? _leaveChannel : null,
                        ),
                  channelList: QuarkChannelList(
                    serverName: serverName,
                    channels: _channelsWithoutOwnBadge(c.channelItems, openId),
                    otherChannels: _channelsWithoutOwnBadge(
                      c.otherChannelItems,
                      openId,
                    ),
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
                                    (channel == null && c.isLoadingChannels),
                                error: messagesError == null
                                    ? null
                                    : Errors.message(
                                        messagesError,
                                        'load the channel',
                                      ),
                                // While searching, the search bar offers
                                // older messages instead.
                                hasMore: matches == null && c.hasOlderMessages,
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
                                pickMoreEmoji: useNativeEmojiKeyboard()
                                    ? (pickerContext, _) =>
                                          showNativeEmojiDialog(pickerContext)
                                    : null,
                                onAnswerPoll: _answerPoll,
                                onClosePoll: _closePoll,
                                onExportPoll: _exportPoll,
                                onEncryptionHelp: _explainEncryption,
                                onOpenLink: (uri) => launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                ),
                                onOpenAttachment: (_, item) =>
                                    unawaited(_openAttachment(item)),
                                onPlayAttachment: (_, item) =>
                                    unawaited(_playAttachment(item)),
                                onSaveAttachmentToDevice: (_, item) =>
                                    unawaited(_saveAttachmentToDevice(item)),
                                onSaveAttachmentToFiles: (_, item) =>
                                    unawaited(_saveAttachmentToFiles(item)),
                                thumbnailBuilder: (context, item) {
                                  final bytes = c.thumbnailFor(item.id);
                                  if (bytes != null && bytes.isNotEmpty) {
                                    return Image.memory(
                                      bytes,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                    );
                                  }
                                  // A message can carry no thumbnail: the
                                  // picture still belongs in the bubble when
                                  // it is small enough to open.
                                  if (item.kind == ChatAttachmentKind.image &&
                                      item.size <=
                                          ChatMessagesController
                                              .maxInlineImageBytes) {
                                    return ChatAttachmentPreview(
                                      load: () =>
                                          c.readAttachmentImage(item.id),
                                    );
                                  }
                                  if (item.kind == ChatAttachmentKind.video &&
                                      item.size <=
                                          ChatMessagesController
                                              .maxVideoPreviewBytes) {
                                    return ChatAttachmentPreview(
                                      load: () => c.videoPreview(item.id),
                                      reportFailure: false,
                                    );
                                  }
                                  return null;
                                },
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
                          isRegenerating: c.isRegeneratingKey,
                          onCheckAgain: c.checkKey,
                          onRegenerate: c.canRegenerateKey
                              ? () => _regenerateKey()
                              : null,
                          onLearnMore: _explainEncryption,
                        ),
                      for (final send in c.outboundSends)
                        ChatFailedSendBar(
                          id: send.id,
                          text: send.text,
                          error: send.failed
                              ? Errors.message(send.error, 'send the message')
                              : null,
                          onRetry: () => c.retry(send.id),
                          onDiscard: () => c.discard(send.id),
                        ),
                      // Chrome pinned to the bottom edge keeps clear of the
                      // rounded display corners and the home indicator
                      // (#2788).
                      QuarkEdgeInset(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: QuarkTokens.of(context).spacingSm,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (c.canPostPoll)
                                QuarkBarIconButton(
                                  key: const ValueKey('chat_new_poll'),
                                  icon: QuarkIcons.poll,
                                  tooltip: 'New poll',
                                  onPressed: () =>
                                      showChatPollEditor(context, chat: c),
                                ),
                              Expanded(
                                child: QuarkMessageComposer(
                                  // A new state per channel. The text is that
                                  // channel's draft, kept for this app session.
                                  key: ValueKey(
                                    'chat_composer_${channel?.id}_$_composerEpoch',
                                  ),
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
                                  onAttach: channel == null
                                      ? null
                                      : () => unawaited(_attachFile()),
                                ),
                              ),
                            ],
                          ),
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

/// A media type for [name], enough for the receiver to draw the tile.
///
/// Known image and video extensions keep a specific type. Anything else
/// follows [fileKindForName], so a photo the table knows is still an image.
String _chatFileMime(String name) {
  return switch (fileExtension(name)) {
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.png' => 'image/png',
    '.gif' => 'image/gif',
    '.webp' => 'image/webp',
    '.heic' || '.heif' => 'image/heic',
    '.mp4' || '.m4v' => 'video/mp4',
    '.mov' => 'video/quicktime',
    '.webm' => 'video/webm',
    '.pdf' => 'application/pdf',
    '.txt' => 'text/plain',
    _ => switch (fileKindForName(name)) {
      FileKind.image => 'image/jpeg',
      FileKind.video => 'video/mp4',
      _ => 'application/octet-stream',
    },
  };
}
