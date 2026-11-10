import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../core/quark_avatar.dart';
import '../core/quark_loader.dart';
import '../models/chat_attachment_item.dart';
import '../models/chat_message_item.dart';
import '../models/chat_poll_answer.dart';
import '../models/chat_permission.dart';
import '../theme/quark_tokens.dart';
import 'quark_message_list/chat_day_separator.dart';
import 'quark_message_list/chat_load_older_row.dart';
import 'quark_message_list/chat_message_row.dart';
import 'quark_message_list/chat_system_line.dart';

/// A channel's messages, newest at the bottom, built lazily so a long history
/// costs only what is on screen.
///
/// [messages] is ordered **newest first**, the order a reversed list builds
/// in, so loading older messages appends to the end. Consecutive messages
/// from one author within [groupWindow] share one avatar and name, a rule
/// across the list marks each new day, and system lines, messages waiting for
/// their key, and deleted messages each draw their own way (see
/// [ChatMessageKind]).
///
/// Loading is the caller's: [isLoading], [error] and [hasMore] come in and
/// [onLoadOlder] goes out. With no messages, loading shows a spinner, an
/// error shows the caller's sentence with a retry that fires [onLoadOlder],
/// and otherwise the list says the channel
/// is empty. With messages, the same states show in a row at the top, and
/// [onLoadOlder] also fires when the list is scrolled within
/// [loadOlderExtent] of the top. It can fire more than once before the caller
/// sets [isLoading], so the caller ignores a request while one is out.
///
/// [onAtBottomChanged] says whether the newest message is in view, which is
/// what a caller needs to know to count a channel as read. It is not
/// deduplicated, so it fires again with the same value as the list scrolls
/// or its content changes, and the caller ignores the repeats.
///
/// Nothing here animates: new messages appear at the bottom in place. A
/// caller that scrolls to the newest message with [controller] checks
/// reduced motion itself and jumps rather than animates when it is on.
///
/// Each text message has a menu, opened by a long press on a touch platform,
/// a right-click, or the three-dot button at its end, which the keyboard
/// reaches. "Copy text" fires [onCopy], "Add reaction" offers the quick emoji
/// and "More emoji", which opens a searchable picker of every emoji (or
/// [pickMoreEmoji], when set) and fires [onReact], and "Delete" fires
/// [onDelete]; the caller asks for
/// confirmation if it wants one. "Delete" is on each message the user may
/// delete: their own, which authorship allows, or anyone's when [permissions]
/// holds [ChatPermission.deleteMessages].
///
/// On macOS, Windows and Linux, in a browser or not, the list is a
/// `SelectionArea`: dragging selects message text, across messages, and the
/// platform's copy shortcut copies it. There a long press is the selection's,
/// not the menu's. On Android and iOS a long press opens the menu, nothing is
/// selectable, and "Copy text" is how text is copied.
///
/// A text message's reactions show under it as chips, one per emoji with its
/// count, highlighted where the user reacted. When [onReact] is set and
/// [permissions] holds [ChatPermission.addReactions] (or is null), each text
/// message gets an add-reaction button offering a short list of emoji and
/// "More emoji" for any other, and
/// tapping a chip fires [onReact] too; the caller decides from its own state
/// whether that adds the user's reaction or takes it back. Waiting, deleted
/// and system lines draw no reactions.
///
/// A poll message draws a `QuarkPollCard`. Its answer fires [onAnswerPoll],
/// which, like reacting, needs [ChatPermission.addReactions] in
/// [permissions] (or null permissions). "Close poll" fires [onClosePoll] and
/// is offered only on the user's own polls, and "Export" fires [onExportPoll]
/// wherever the results are visible.
///
/// A text message's attachments are drawn under its body, each as a
/// `ChatAttachmentTile`. An empty body with attachments shows only those.
/// [thumbnailBuilder] supplies an image's preview. A tap fires
/// [onOpenAttachment], and a video's play control fires [onPlayAttachment].
/// [onSaveAttachmentToDevice] and [onSaveAttachmentToFiles] are that tile's
/// save actions.
///
/// With [onOpenLink] set, each `http://`, `https://` or `www.` address in a
/// text message is drawn as a link, and a tap fires [onOpenLink] with its
/// [Uri]; the caller opens it. An unverified sender's message, and every
/// system line, stays plain text.
///
/// Each `@name` in a text message that names one of [mentionNames] is drawn
/// as a mention, and a message that mentions [currentUserName] is highlighted
/// (#2623). Chat is end-to-end encrypted, so a mention is only that text
/// inside the message: the list finds it, and nothing else says who was
/// mentioned.
///
/// With [onEncryptionHelp] set, each system line about encryption
/// ([ChatMessageItem.isEncryptionEvent]) and each unverified system line ends
/// in a "(?)" button with [encryptionHelpTooltip]; a tap fires
/// [onEncryptionHelp], and the caller explains, usually with a
/// `QuarkEncryptionHelpDialog`.
///
/// [permissions] without [ChatPermission.readMessages] is someone who manages
/// the channel without being in the conversation. They get [notMemberText]
/// in place of the list: no messages, no spinner and no waiting for a key,
/// because no key is coming.
///
/// Key prefixes: `message_<id>` on each message, `message_mention_<id>` on
/// the highlight of one that mentions the user, `message_body_<id>` on a
/// text message's body (a link is reached by its text inside it),
/// `message_menu_<id>` on its menu button, `message_copy_<id>`,
/// `message_menu_react_<id>` and `message_delete_<id>` on the menu's entries,
/// `message_menu_react_<id>_<emoji>` on each emoji the menu offers,
/// `message_react_<id>` on its add-reaction button,
/// `message_react_<id>_<emoji>` on each emoji that button offers,
/// `message_react_<id>_more` on its "More emoji",
/// `message_menu_react_<id>_more` on the menu's "More emoji",
/// `message_emoji_search_<id>` and `message_emoji_close_<id>` on the full
/// picker,
/// `message_reaction_<id>_<emoji>` on each reaction chip,
/// `message_help_<id>` on a system line's "(?)", those of `QuarkPollCard`
/// on a poll, those of `ChatAttachmentTile` on an attachment,
/// `message_list_load_older` on the load button,
/// `message_list_retry` on the retry button, and `message_list_not_member`
/// on the not-a-member pane.
///
/// ```dart
/// QuarkMessageList(
///   messages: controller.messages,
///   isLoading: controller.isLoadingOlder,
///   error: olderError,
///   hasMore: controller.hasOlder,
///   onLoadOlder: controller.loadOlder,
///   permissions: controller.selectedPermissions,
///   currentUserId: controller.userId,
///   mentionNames: controller.mentionNames,
///   currentUserName: controller.userName,
///   onCopy: (id) => copy(controller.textOf(id)),
///   onDelete: controller.deleteMessage,
///   onReact: controller.toggleReaction,
///   onOpenLink: (uri) => launchUrl(uri),
///   onOpenAttachment: controller.openAttachment,
///   onPlayAttachment: controller.playAttachment,
///   onSaveAttachmentToDevice: (id, item) => saveToDevice(item),
///   onSaveAttachmentToFiles: (id, item) => saveToFiles(item),
///   thumbnailBuilder: (context, item) => thumbnailOf(item),
///   onAtBottomChanged: controller.setAtBottom,
///   avatarBuilder: (context, userId) => AppAvatar(userId: userId),
/// );
/// ```
class QuarkMessageList extends StatefulWidget {
  /// Creates the list of [messages], newest first.
  const QuarkMessageList({
    required this.messages,
    this.isLoading = false,
    this.error,
    this.hasMore = false,
    this.onLoadOlder,
    this.permissions,
    this.currentUserId,
    this.mentionNames = const [],
    this.currentUserName,
    this.onCopy,
    this.onDelete,
    this.onReact,
    this.pickMoreEmoji,
    this.onOpenLink,
    this.onAnswerPoll,
    this.onClosePoll,
    this.onExportPoll,
    this.onOpenAttachment,
    this.onPlayAttachment,
    this.onSaveAttachmentToDevice,
    this.onSaveAttachmentToFiles,
    this.thumbnailBuilder,
    this.onEncryptionHelp,
    this.onAtBottomChanged,
    this.avatarBuilder,
    this.controller,
    super.key,
  });

  /// The tooltip on an encryption line's "(?)".
  static const String encryptionHelpTooltip = 'What does this mean?';

  /// How close together one author's messages have to be to share a header.
  static const Duration groupWindow = Duration(minutes: 5);

  /// How near the top, in pixels, scrolling asks for older messages.
  static const double loadOlderExtent = 400;

  /// How far from the bottom, in pixels, still counts as at the bottom for
  /// [onAtBottomChanged].
  static const double atBottomTolerance = 1;

  /// The diameter of each group's avatar.
  static const double avatarSize = 32;

  /// The messages, newest first.
  final List<ChatMessageItem> messages;

  /// Whether messages are loading: the first page when [messages] is empty,
  /// older ones otherwise.
  final bool isLoading;

  /// A sentence saying why messages could not be loaded, composed by the
  /// caller.
  final String? error;

  /// Whether there are messages older than the oldest in [messages].
  final bool hasMore;

  /// Asks for the page of messages older than the oldest shown, or for the
  /// first page when [messages] is empty. Fires from the load button, the
  /// retry button, and scrolling near the top while [hasMore]. Null never
  /// asks, and shows no retry.
  final VoidCallback? onLoadOlder;

  /// What the signed-in account may do in the channel.
  /// [ChatPermission.deleteMessages] puts "Delete" in the menu of everyone's
  /// messages, and a set without [ChatPermission.readMessages] shows
  /// [notMemberText] instead of the list. Null checks nothing and offers
  /// delete on the user's own messages only.
  final Set<ChatPermission>? permissions;

  /// The signed-in account's id, whose own messages always offer "Delete".
  /// Null matches no author.
  final String? currentUserId;

  /// The names an `@mention` can resolve to, usually the channel's members.
  /// Empty draws no mentions.
  final List<String> mentionNames;

  /// The signed-in account's name as it is in [mentionNames]. A message that
  /// mentions it is highlighted. Null highlights nothing.
  final String? currentUserName;

  /// Called with a text message's id to copy its text; the clipboard is the
  /// caller's. Null leaves "Copy text" out of every menu.
  final ValueChanged<String>? onCopy;

  /// Called with a message's id to delete it. Null leaves "Delete" out of
  /// every menu.
  final ValueChanged<String>? onDelete;

  /// Called with a message's id and an emoji when the user picks that emoji
  /// or taps its chip. Null, or [permissions] without
  /// [ChatPermission.addReactions], only shows reactions.
  final void Function(String messageId, String emoji)? onReact;

  /// Asks for an emoji beyond the quick six. Null opens the built-in
  /// searchable picker. A null result fires no [onReact].
  final Future<String?> Function(BuildContext context, String messageId)?
  pickMoreEmoji;

  /// Called with a web address in a text message when it is tapped, for the
  /// caller to open. Null draws every message as plain text.
  final ValueChanged<Uri>? onOpenLink;

  /// Called with a poll message's id and the user's answer to it. Null, or
  /// [permissions] without [ChatPermission.addReactions], draws every poll's
  /// inputs disabled.
  final void Function(String messageId, ChatPollAnswer answer)? onAnswerPoll;

  /// Called with the id of a poll the user posted, to close it.
  final ValueChanged<String>? onClosePoll;

  /// Called with a poll message's id to export its results.
  final ValueChanged<String>? onExportPoll;

  /// Called with a message's id and an image or a file attached to it when
  /// the tile is tapped. Null leaves those tiles inert.
  final void Function(String messageId, ChatAttachmentItem attachment)?
  onOpenAttachment;

  /// Called with a message's id and a video attached to it when its play
  /// control is tapped. Null leaves the control disabled.
  final void Function(String messageId, ChatAttachmentItem attachment)?
  onPlayAttachment;

  /// Called with a message's id and an attachment when "Save to device" is
  /// tapped. Null leaves that action out.
  final void Function(String messageId, ChatAttachmentItem attachment)?
  onSaveAttachmentToDevice;

  /// Called with a message's id and an attachment when "Save to my files" is
  /// tapped. Null leaves that action out.
  final void Function(String messageId, ChatAttachmentItem attachment)?
  onSaveAttachmentToFiles;

  /// Builds a preview for an image attachment. Null, or a builder that
  /// returns null, shows the file name on that tile.
  final Widget? Function(BuildContext context, ChatAttachmentItem attachment)?
  thumbnailBuilder;

  /// Called when an encryption or unverified system line's "(?)" is tapped,
  /// for the caller to explain. Null draws no "(?)".
  final VoidCallback? onEncryptionHelp;

  /// Called with whether the newest message is in view: the list sits within
  /// [atBottomTolerance] of its bottom, which a list too short to scroll
  /// always does. Fires after the first layout, on every scroll, and when
  /// the content or the viewport changes size, so it repeats the same value
  /// and the caller ignores repeats. Never fires while there is no list:
  /// loading, the error, the empty channel and [notMemberText].
  final ValueChanged<bool>? onAtBottomChanged;

  /// Builds the avatar for an author's id, [avatarSize] across. Null draws
  /// a [QuarkAvatar] with the author's initials.
  final Widget Function(BuildContext context, String userId)? avatarBuilder;

  /// The list's scroll controller, for a caller that jumps to the newest
  /// message. Offset zero is the bottom.
  final ScrollController? controller;

  /// Shown in place of the list to someone who manages the channel but can't
  /// read it.
  static const String notMemberText =
      'You are not a member of this conversation';

  /// Whether [newer] starts a new header group after [older], the message
  /// before it in time.
  static bool startsGroup(ChatMessageItem newer, ChatMessageItem? older) =>
      older == null ||
      !isSameDay(newer.sentAt, older.sentAt) ||
      newer.kind == ChatMessageKind.system ||
      older.kind == ChatMessageKind.system ||
      newer.authorId != older.authorId ||
      newer.sentAt.difference(older.sentAt) > groupWindow;

  /// Whether [a] and [b] fall on the same calendar day.
  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  State<QuarkMessageList> createState() => _QuarkMessageListState();
}

/// Scroll position and the count of messages that arrived while it was away
/// from the newest one. Both are view state the list has to keep itself.
class _QuarkMessageListState extends State<QuarkMessageList> {
  ScrollController? _owned;
  final Set<String> _ids = {};
  bool _atBottom = true;
  int _newCount = 0;

  ScrollController get _scroll =>
      widget.controller ?? (_owned ??= ScrollController());

  @override
  void initState() {
    super.initState();
    _remember(widget.messages);
  }

  @override
  void didUpdateWidget(QuarkMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _countArrivals(widget.messages);
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  void _remember(List<ChatMessageItem> messages) {
    _ids
      ..clear()
      ..addAll(messages.map((message) => message.id));
  }

  /// Counts messages inserted at the newest end while the viewport is away
  /// from it. Older pages sit at the other end and do not count, and a list
  /// that shares no id with the one before it is a different channel.
  void _countArrivals(List<ChatMessageItem> incoming) {
    if (incoming.isEmpty ||
        (_ids.isNotEmpty &&
            incoming.every((message) => !_ids.contains(message.id)))) {
      _remember(incoming);
      _newCount = 0;
      return;
    }
    var added = 0;
    if (_isAwayFromBottom) {
      for (final message in incoming) {
        if (_ids.contains(message.id)) break;
        added++;
      }
    }
    _remember(incoming);
    if (!_isAwayFromBottom) {
      _newCount = 0;
    } else if (added > 0) {
      _newCount += added;
    }
  }

  bool get _isAwayFromBottom {
    final scroll = widget.controller ?? _owned;
    if (scroll == null || !scroll.hasClients) return false;
    return scroll.position.extentBefore > QuarkMessageList.atBottomTolerance;
  }

  void _reportAtBottom(bool atBottom) {
    widget.onAtBottomChanged?.call(atBottom);
    if (atBottom == _atBottom && (!atBottom || _newCount == 0)) return;
    setState(() {
      _atBottom = atBottom;
      if (atBottom) _newCount = 0;
    });
  }

  void _jumpToLatest() {
    final scroll = _scroll;
    if (scroll.hasClients) scroll.jumpTo(0);
    if (_newCount == 0 && _atBottom) return;
    setState(() {
      _newCount = 0;
      _atBottom = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final messages = widget.messages;
    final isLoading = widget.isLoading;
    final hasMore = widget.hasMore;
    final error = widget.error;
    final onLoadOlder = widget.onLoadOlder;
    final avatarBuilder = widget.avatarBuilder;
    final onCopy = widget.onCopy;
    final onDelete = widget.onDelete;
    final permissions = widget.permissions;
    final deletesAny =
        permissions?.contains(ChatPermission.deleteMessages) ?? false;
    final reacts =
        permissions == null ||
        permissions.contains(ChatPermission.addReactions);
    final onReact = reacts ? widget.onReact : null;
    final onAnswerPoll = reacts ? widget.onAnswerPoll : null;
    final onClosePoll = widget.onClosePoll;
    final onExportPoll = widget.onExportPoll;

    if (permissions != null &&
        !permissions.contains(ChatPermission.readMessages)) {
      return const EmptyStateWidget(
        key: ValueKey('message_list_not_member'),
        icon: QuarkIcons.lock_outline,
        headline: QuarkMessageList.notMemberText,
        subtext: 'You can manage it, but its messages are not shared with you.',
      );
    }

    if (messages.isEmpty) {
      if (isLoading) return const Center(child: QuarkLoader());
      if (error != null) {
        // The first page failed: the same error and retry as the top row.
        return Center(
          child: ChatLoadOlderRow(
            isLoading: false,
            hasMore: false,
            error: error,
            onLoadOlder: onLoadOlder,
          ),
        );
      }
      return const EmptyStateWidget(
        icon: QuarkIcons.forum_outlined,
        headline: 'No messages yet',
        subtext: 'Say hello.',
      );
    }

    final selectable = switch (Theme.of(context).platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => false,
    };

    // Reversed, so the bottom is the start: nothing before it means the
    // newest message is in view. Depth zero is the list itself, not a
    // scrollable inside a message.
    void reportAtBottom(int depth, ScrollMetrics metrics) {
      if (depth == 0) {
        _reportAtBottom(
          metrics.extentBefore <= QuarkMessageList.atBottomTolerance,
        );
      }
    }

    final list = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        reportAtBottom(notification.depth, notification.metrics);
        if (hasMore &&
            !isLoading &&
            error == null &&
            onLoadOlder != null &&
            notification.metrics.extentAfter <
                QuarkMessageList.loadOlderExtent) {
          onLoadOlder();
        }
        return false;
      },
      // Scroll metrics change without a scroll on the first layout, when
      // the list is too short to scroll, and when a message arrives.
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          reportAtBottom(notification.depth, notification.metrics);
          return false;
        },
        child: ListView.builder(
          controller: _scroll,
          reverse: true,
          // A phone keyboard stays up until something closes it (#4051).
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.symmetric(vertical: tokens.spacingSm),
          itemCount: messages.length + 1,
          itemBuilder: (context, index) {
            if (index == messages.length) {
              return ChatLoadOlderRow(
                isLoading: isLoading,
                hasMore: hasMore,
                error: error,
                onLoadOlder: onLoadOlder,
              );
            }
            final message = messages[index];
            final older = index + 1 < messages.length
                ? messages[index + 1]
                : null;
            final startsDay =
                older == null ||
                !QuarkMessageList.isSameDay(message.sentAt, older.sentAt);

            return Column(
              key: ValueKey('message_${message.id}'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (startsDay) ChatDaySeparator(date: message.sentAt),
                if (message.kind == ChatMessageKind.system)
                  ChatSystemLine(
                    message: message,
                    onHelp: widget.onEncryptionHelp,
                  )
                else
                  ChatMessageRow(
                    message: message,
                    avatarSize: QuarkMessageList.avatarSize,
                    longPressOpensMenu: !selectable,
                    onCopy:
                        onCopy == null || message.kind != ChatMessageKind.text
                        ? null
                        : () => onCopy(message.id),
                    onDelete:
                        onDelete == null ||
                            message.kind != ChatMessageKind.text ||
                            !(deletesAny ||
                                message.authorId == widget.currentUserId)
                        ? null
                        : () => onDelete(message.id),
                    onReact: onReact == null
                        ? null
                        : (emoji) => onReact(message.id, emoji),
                    pickMoreEmoji: onReact == null
                        ? null
                        : widget.pickMoreEmoji,
                    onOpenLink: widget.onOpenLink,
                    onAnswerPoll: onAnswerPoll == null
                        ? null
                        : (answer) => onAnswerPoll(message.id, answer),
                    onClosePoll:
                        onClosePoll == null ||
                            message.authorId != widget.currentUserId
                        ? null
                        : () => onClosePoll(message.id),
                    onExportPoll: onExportPoll == null
                        ? null
                        : () => onExportPoll(message.id),
                    onOpenAttachment: widget.onOpenAttachment == null
                        ? null
                        : (attachment) =>
                              widget.onOpenAttachment!(message.id, attachment),
                    onPlayAttachment: widget.onPlayAttachment == null
                        ? null
                        : (attachment) =>
                              widget.onPlayAttachment!(message.id, attachment),
                    onSaveAttachmentToDevice:
                        widget.onSaveAttachmentToDevice == null
                        ? null
                        : (attachment) => widget.onSaveAttachmentToDevice!(
                            message.id,
                            attachment,
                          ),
                    onSaveAttachmentToFiles:
                        widget.onSaveAttachmentToFiles == null
                        ? null
                        : (attachment) => widget.onSaveAttachmentToFiles!(
                            message.id,
                            attachment,
                          ),
                    thumbnailBuilder: widget.thumbnailBuilder,
                    mentionNames: widget.mentionNames,
                    selfName: widget.currentUserName,
                    avatar: !QuarkMessageList.startsGroup(message, older)
                        ? null
                        : avatarBuilder != null
                        ? SizedBox.square(
                            dimension: QuarkMessageList.avatarSize,
                            child: avatarBuilder(context, message.authorId),
                          )
                        : QuarkAvatar(
                            id: message.authorId,
                            name: message.authorName,
                            size: QuarkMessageList.avatarSize,
                          ),
                  ),
              ],
            );
          },
        ),
      ),
    );
    // An empty selection toolbar: a right-click belongs to the message's
    // menu, and the copy shortcut works without one. The builder cannot be
    // null, which a touch long press on a desktop platform dereferences.
    final body = selectable
        ? SelectionArea(
            contextMenuBuilder: (_, _) => const SizedBox.shrink(),
            child: list,
          )
        : list;
    // The list stays the stack's first child whether or not the pill is
    // showing. Swapping it in only when a message arrives rebuilds the
    // scrollable and drops a reversed list back at the newest message.
    final label = _newCount == 1 ? '1 new message' : '$_newCount new messages';
    return Stack(
      fit: StackFit.expand,
      children: [
        body,
        if (_newCount > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: tokens.spacingMd,
            child: Center(
              child: TextButton(
                key: const ValueKey('message_list_jump'),
                style: TextButton.styleFrom(
                  foregroundColor: tokens.primaryForeground,
                  backgroundColor: tokens.primary,
                  padding: EdgeInsets.symmetric(
                    horizontal: tokens.spacingMd,
                    vertical: tokens.spacingSm,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusLg),
                  ),
                  minimumSize: const Size(0, kMinInteractiveDimension),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: _jumpToLatest,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(QuarkIcons.arrow_downward_rounded, size: 18),
                    SizedBox(width: tokens.spacingXs),
                    Text(label),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
