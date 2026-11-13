import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:quark_icons/quark_icons.dart';

import '../../core/quark_menu_button.dart';
import '../../core/show_quark_menu.dart';
import '../../models/chat_attachment_item.dart';
import '../../models/chat_message_item.dart';
import '../../models/chat_poll_answer.dart';
import '../../models/quark_menu_entry.dart';
import '../../theme/quark_tokens.dart';
import '../chat_attachment_tile.dart';
import '../chat_mentions.dart';
import '../quark_poll_card.dart';
import 'chat_emoji_picker.dart';
import 'chat_message_row/chat_message_body.dart';
import 'chat_message_row/chat_message_context_menu.dart';
import 'chat_message_row/chat_reaction_bar.dart';
import 'chat_message_row/chat_reaction_picker.dart';

/// One message a person sent, with the author's avatar, name and time above
/// it when it starts a group, or indented under the group's header when it
/// does not.
///
/// Draws the body of a text message, a poll's `QuarkPollCard`, the "waiting
/// for key" placeholder, or a deleted message's tombstone, according to
/// [ChatMessageItem.kind]. A text message's [ChatMessageItem.attachments]
/// are `ChatAttachmentTile`s under the body. An empty body with attachments
/// shows only those. Save actions on a tile call [onSaveAttachmentToDevice]
/// and [onSaveAttachmentToFiles]. A poll's card answers with [onAnswerPoll],
/// closes with [onClosePoll] and exports with [onExportPoll]. System
/// lines are a `ChatSystemLine` instead. A text message's reactions sit under
/// its body as a `ChatReactionBar`, and [onReact] adds a `ChatReactionPicker`
/// at the row's end as the quick way to react. "More emoji" there, and in the
/// menu, opens the full picker, or [pickMoreEmoji] when the caller supplies
/// one.
///
/// A text message's actions are "Copy text" with [onCopy], "Add reaction"
/// with [onReact], and "Delete" with [onDelete]. A null callback leaves its
/// action out, and with all three null there are none. They come in one of
/// two presentations, which [touchMenu] picks:
///
/// - **Pointer** (the default, and what `QuarkMessageList` uses on the
///   desktop platforms): a menu through `showQuarkMenu`, opened at the
///   pointer by a right-click or by the three-dot button at the row's end,
///   which the keyboard reaches. "Add reaction" opens the picker's emoji and
///   "More emoji" as a second menu in the same place. A long press is left
///   to whatever is above the row, such as a `SelectionArea`.
/// - **Touch** (iOS and Android): a long press opens a
///   `ChatMessageContextMenu`, which lifts a copy of the message over a
///   blurred page, with the emoji as a bar above it and the other actions
///   in full under it, all clear of the keyboard. There is no three-dot
///   button, and a screen reader finds every action on the row as a custom
///   action, "Add reaction" opening the context menu at its bar. A
///   right-click still opens the pointer menu.
///
/// With [onOpenLink] set, the web addresses in a text message are links (see
/// `ChatMessageBody`), except in a message whose sender is unverified: an
/// address from someone who may not be who they claim is not put one tap
/// away.
///
/// Each `@name` in a text message that names one of [mentionNames] is drawn
/// as a mention (see `ChatMessageBody`). A message that mentions [selfName],
/// the reader, stands on a tint of the primary color with a bar down its
/// leading edge, and a screen reader hears "Mentions you". An unverified
/// message draws no mentions: its text is not the sender's.
///
/// While a menu a long press or right-click opened is open, the row stands
/// on a tint of the primary color. It clears when an action is chosen or the
/// menu is dismissed, and "Add reaction" keeps it until its emoji menu closes.
///
/// A part of `QuarkMessageList`, tested through it.
///
/// Key prefixes: `message_menu_open_<id>` on the row's tint (its color is
/// null when no menu is open), `message_mention_<id>` on the highlight of a message that
/// mentions the reader, `message_body_<id>` on a text message's body,
/// `message_menu_<id>` on the menu button, `message_copy_<id>`,
/// `message_menu_react_<id>` and `message_delete_<id>` on the menu's entries
/// (the touch menu has no `message_menu_react_<id>`: its bar replaces it),
/// `message_menu_react_<id>_<emoji>` on each emoji "Add reaction" or the
/// touch menu's bar offers, `message_menu_react_<id>_more` on their "More
/// emoji", `message_context_copy_<id>` and `message_context_lift_<id>` on the
/// touch menu's copy of the message, and those of `ChatReactionBar`,
/// `ChatReactionPicker`, `ChatAttachmentTile` and `QuarkPollCard`. While the
/// touch menu is open its copy is a second row, so the row's own keys are
/// found twice.
class ChatMessageRow extends StatefulWidget {
  /// Creates the row for [message].
  const ChatMessageRow({
    required this.message,
    required this.avatar,
    this.avatarSize = 32,
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
    this.mentionNames = const [],
    this.selfName,
    this.touchMenu = false,
    super.key,
  });

  /// The message to draw.
  final ChatMessageItem message;

  /// The author's avatar, which also means this row starts a group and shows
  /// the author's name and the time. Null indents the row under the group
  /// above it.
  final Widget? avatar;

  /// The width reserved for the avatar, so grouped rows line up under it.
  final double avatarSize;

  /// Copies the message's text. Null leaves "Copy text" out of the menu.
  final VoidCallback? onCopy;

  /// Deletes the message. Null leaves "Delete" out of the menu.
  final VoidCallback? onDelete;

  /// Adds or takes back a reaction, with its emoji, from the picker, the menu
  /// or a reaction chip. Null leaves the picker and the menu's "Add reaction"
  /// out and the chips inert.
  final ValueChanged<String>? onReact;

  /// Asks for an emoji beyond the quick six. Null opens the built-in picker.
  /// A null result adds no reaction.
  final Future<String?> Function(BuildContext context, String messageId)?
  pickMoreEmoji;

  /// Called with a web address in the message's text when it is tapped. Null
  /// draws the text with no links, as an unverified message always is.
  final ValueChanged<Uri>? onOpenLink;

  /// Answers a poll message. Null draws its card's inputs disabled.
  final ValueChanged<ChatPollAnswer>? onAnswerPoll;

  /// Closes a poll message. Null leaves its card's "Close poll" out.
  final VoidCallback? onClosePoll;

  /// Exports a poll message's results. Null leaves its card's "Export" out.
  final VoidCallback? onExportPoll;

  /// Called with an image or a file attached to this message when its tile
  /// is tapped. Null leaves those tiles inert.
  final ValueChanged<ChatAttachmentItem>? onOpenAttachment;

  /// Called with a video attached to this message when its play control is
  /// tapped. Null leaves the control disabled.
  final ValueChanged<ChatAttachmentItem>? onPlayAttachment;

  /// Called with an attachment when its "Save to device" action is tapped.
  /// Null leaves that action out.
  final ValueChanged<ChatAttachmentItem>? onSaveAttachmentToDevice;

  /// Called with an attachment when its "Save to my files" action is tapped.
  /// Null leaves that action out.
  final ValueChanged<ChatAttachmentItem>? onSaveAttachmentToFiles;

  /// Builds a preview for an image attachment. Null, or a builder that
  /// returns null, shows the file name on that tile.
  final Widget? Function(BuildContext context, ChatAttachmentItem item)?
  thumbnailBuilder;

  /// The names an `@mention` in the message can resolve to. Empty draws none.
  final List<String> mentionNames;

  /// The reader's own name. A message that mentions it is highlighted. Null
  /// highlights nothing.
  final String? selfName;

  /// Whether the row uses the touch presentation: a long press opens the
  /// `ChatMessageContextMenu`, there is no three-dot button, and the actions
  /// are the row's semantics custom actions. False is the pointer
  /// presentation, which leaves the long press to whatever is above the row,
  /// such as a `SelectionArea`.
  final bool touchMenu;

  /// The actions of a text message, as menu entries; empty for anything
  /// else. [reactionMenuAt] is where "Add reaction" opens its emoji, read
  /// when it does, and [onReactionMenu] gets that menu's future. A null
  /// [reactionMenuAt] leaves "Add reaction" out, for the touch menu, whose
  /// bar offers the emoji instead.
  List<QuarkMenuEntry> menuEntries(
    BuildContext context, {
    Offset Function()? reactionMenuAt,
    ValueChanged<Future<void>>? onReactionMenu,
  }) {
    final onCopy = this.onCopy;
    final onDelete = this.onDelete;
    final onReact = this.onReact;
    final pickMoreEmoji = this.pickMoreEmoji;
    if (message.kind != ChatMessageKind.text) return const [];
    return [
      if (onCopy != null)
        QuarkMenuEntry(
          key: ValueKey('message_copy_${message.id}'),
          label: 'Copy text',
          icon: QuarkIcons.content_copy,
          onSelected: onCopy,
        ),
      if (onReact != null && reactionMenuAt != null)
        QuarkMenuEntry(
          key: ValueKey('message_menu_react_${message.id}'),
          label: 'Add reaction',
          icon: QuarkIcons.add_reaction_outlined,
          onSelected: () {
            if (!context.mounted) return;
            final emojiMenu = showQuarkMenu(
              context,
              position: reactionMenuAt(),
              entries: [
                for (final emoji in ChatReactionPicker.choices)
                  QuarkMenuEntry(
                    key: ValueKey('message_menu_react_${message.id}_$emoji'),
                    label: emoji,
                    onSelected: () => onReact(emoji),
                  ),
                QuarkMenuEntry(
                  key: ValueKey('message_menu_react_${message.id}_more'),
                  label: 'More emoji',
                  icon: QuarkIcons.search,
                  onSelected: () => requestMoreEmoji(
                    context,
                    messageId: message.id,
                    onPick: onReact,
                    pickMore: pickMoreEmoji,
                  ),
                ),
              ],
            );
            onReactionMenu?.call(emojiMenu);
          },
        ),
      if (onDelete != null)
        QuarkMenuEntry(
          key: ValueKey('message_delete_${message.id}'),
          label: 'Delete',
          icon: QuarkIcons.delete_outline,
          destructive: true,
          onSelected: onDelete,
        ),
    ];
  }

  /// The widest a message's text runs before it wraps, about 80 characters
  /// of body text: a line across a desktop window is too long to read
  /// (#3257).
  static const double maxBodyWidth = 600;

  /// The time drawn beside the author's name, as `HH:mm`.
  static String timeOf(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  @override
  State<ChatMessageRow> createState() => _ChatMessageRowState();
}

/// The state of a [ChatMessageRow]: whether a menu it opened is open, which
/// tints the row until that menu, and the emoji menu "Add reaction" opens in
/// its place, has closed.
class _ChatMessageRowState extends State<ChatMessageRow> {
  bool _menuOpen = false;

  /// Tints the row until [menu] has closed.
  Future<void> _tintWhile(Future<void> Function() menu) async {
    setState(() => _menuOpen = true);
    try {
      await menu();
    } finally {
      if (mounted) setState(() => _menuOpen = false);
    }
  }

  /// Opens the pointer menu at [position].
  Future<void> _openMenu(Offset position) => _tintWhile(() async {
    // "Add reaction" opens its emoji menu as the first one closes; that
    // future is waited on too, so the tint does not blink off between them.
    Future<void>? emojiMenu;
    await showQuarkMenu(
      context,
      position: position,
      entries: widget.menuEntries(
        context,
        reactionMenuAt: () => position,
        onReactionMenu: (menu) => emojiMenu = menu,
      ),
    );
    await emojiMenu;
  });

  /// Opens the touch menu over this row.
  Future<void> _openContextMenu() => _tintWhile(() {
    final row = widget;
    final onReact = row.onReact;
    final tokens = QuarkTokens.of(context);
    return showChatMessageContextMenu(
      context,
      messageId: row.message.id,
      indent: tokens.spacingMd + row.avatarSize + tokens.spacingSm,
      // The row as it looks, with nothing to tap: no menu and no picker.
      copy: ChatMessageRow(
        message: row.message,
        avatar: row.avatar,
        avatarSize: row.avatarSize,
        onOpenLink: row.onOpenLink,
        thumbnailBuilder: row.thumbnailBuilder,
        mentionNames: row.mentionNames,
        selfName: row.selfName,
        touchMenu: true,
      ),
      entries: row.menuEntries(context),
      onReact: onReact,
      onMoreEmoji: onReact == null
          ? null
          : () => requestMoreEmoji(
              context,
              messageId: row.message.id,
              onPick: onReact,
              pickMore: row.pickMoreEmoji,
            ),
    );
  });

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final message = widget.message;
    final avatarSize = widget.avatarSize;
    final onCopy = widget.onCopy;
    final onDelete = widget.onDelete;
    final onOpenLink = widget.onOpenLink;
    final touchMenu = widget.touchMenu;
    final avatar = widget.avatar;
    final onReact = widget.onReact;
    final reacts = message.kind == ChatMessageKind.text;
    final selfName = widget.selfName;
    final mentionNames = reacts && !message.isUnverified
        ? widget.mentionNames
        : const <String>[];
    final mentionsSelf =
        selfName != null &&
        ChatMentions.mentions(message.body, mentionNames, selfName);
    final hasMenu =
        reacts && (onCopy != null || onReact != null || onDelete != null);
    final poll = message.poll;
    final muted = TextStyle(
      color: tokens.mutedForeground,
      fontStyle: FontStyle.italic,
    );

    final body = switch (message.kind) {
      ChatMessageKind.waitingForKey => Row(
        children: [
          Icon(QuarkIcons.key, size: 16, color: tokens.mutedForeground),
          SizedBox(width: tokens.spacingXs),
          Flexible(
            child: Text(
              'Waiting for the key to read this message',
              style: muted,
            ),
          ),
        ],
      ),
      ChatMessageKind.deleted => Row(
        children: [
          Icon(
            QuarkIcons.delete_outline,
            size: 16,
            color: tokens.mutedForeground,
          ),
          SizedBox(width: tokens.spacingXs),
          Flexible(child: Text('This message was deleted', style: muted)),
        ],
      ),
      ChatMessageKind.poll =>
        poll == null
            ? const SizedBox.shrink()
            // The card's border would touch the author's name above it.
            : Padding(
                padding: EdgeInsets.only(top: tokens.spacingXs),
                child: QuarkPollCard(
                  id: message.id,
                  poll: poll,
                  onAnswer: widget.onAnswerPoll,
                  onClose: widget.onClosePoll,
                  onExport: widget.onExportPoll,
                ),
              ),
      ChatMessageKind.text || ChatMessageKind.system => ChatMessageBody(
        key: ValueKey('message_body_${message.id}'),
        text: message.body,
        style: TextStyle(
          color: message.isUnverified ? tokens.warning : tokens.foreground,
        ),
        onOpenLink: reacts && !message.isUnverified ? onOpenLink : null,
        mentionNames: mentionNames,
        selfName: selfName,
      ),
    };

    final tinted = DecoratedBox(
      key: ValueKey('message_menu_open_${message.id}'),
      decoration: BoxDecoration(
        color: _menuOpen ? tokens.primary.withValues(alpha: 0.16) : null,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: hasMenu && touchMenu ? _openContextMenu : null,
        onSecondaryTapUp: hasMenu
            ? (details) => _openMenu(details.globalPosition)
            : null,
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: tokens.spacingMd,
            top: avatar == null ? tokens.spacingXs : tokens.spacingSm,
            end: tokens.spacingMd,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: avatarSize, child: avatar),
              SizedBox(width: tokens.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (avatar != null)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              message.authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.foreground,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(width: tokens.spacingSm),
                          Text(
                            ChatMessageRow.timeOf(message.sentAt),
                            style: TextStyle(
                              color: tokens.mutedForeground,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    // The buttons stand beside the body, not the header: their
                    // 48dp sets the height of a short message, and beside the
                    // header they would set it short of the rest (#2890). They
                    // sit at the body's foot, level with its reactions: a
                    // reversed list grows a row upward, and from the top the
                    // first reaction moved the button just used from under the
                    // pointer and the focus ring (#3257).
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          // At least as tall as the buttons, with the body at
                          // its top, so the buttons' foot is the body's.
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: kMinInteractiveDimension,
                            ),
                            child: Align(
                              alignment: AlignmentDirectional.topStart,
                              heightFactor: 1,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: ChatMessageRow.maxBodyWidth,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (message.body.isNotEmpty ||
                                        message.kind != ChatMessageKind.text ||
                                        message.attachments.isEmpty)
                                      body,
                                    if (reacts)
                                      for (final attachment
                                          in message.attachments)
                                        Padding(
                                          padding: EdgeInsets.only(
                                            top: tokens.spacingXs,
                                          ),
                                          child: ChatAttachmentTile(
                                            item: attachment,
                                            thumbnailBuilder:
                                                widget.thumbnailBuilder,
                                            onOpen:
                                                widget.onOpenAttachment == null
                                                ? null
                                                : () =>
                                                      widget.onOpenAttachment!(
                                                        attachment,
                                                      ),
                                            onPlay:
                                                widget.onPlayAttachment == null
                                                ? null
                                                : () =>
                                                      widget.onPlayAttachment!(
                                                        attachment,
                                                      ),
                                            onSaveToDevice:
                                                widget.onSaveAttachmentToDevice ==
                                                    null
                                                ? null
                                                : () =>
                                                      widget
                                                          .onSaveAttachmentToDevice!(
                                                        attachment,
                                                      ),
                                            onSaveToFiles:
                                                widget.onSaveAttachmentToFiles ==
                                                    null
                                                ? null
                                                : () =>
                                                      widget
                                                          .onSaveAttachmentToFiles!(
                                                        attachment,
                                                      ),
                                          ),
                                        ),
                                    if (reacts && message.reactions.isNotEmpty)
                                      ChatReactionBar(
                                        messageId: message.id,
                                        reactions: message.reactions,
                                        onToggle: onReact,
                                      ),
                                    if (message.isUnverified)
                                      Row(
                                        children: [
                                          Icon(
                                            QuarkIcons.warning_amber,
                                            size: 14,
                                            color: tokens.warning,
                                          ),
                                          SizedBox(width: tokens.spacingXs),
                                          Flexible(
                                            child: Text(
                                              'Unverified',
                                              style: TextStyle(
                                                color: tokens.warning,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (reacts && onReact != null)
                          ChatReactionPicker(
                            messageId: message.id,
                            onPick: onReact,
                            pickMoreEmoji: widget.pickMoreEmoji,
                          ),
                        if (hasMenu && !touchMenu)
                          // The same 48dp touch target as the picker beside it,
                          // so the two glyphs share a center (#2605). The
                          // Builder makes the button the anchor of "Add
                          // reaction".
                          Builder(
                            builder: (context) => QuarkMenuButton(
                              key: ValueKey('message_menu_${message.id}'),
                              tooltip: 'Message actions',
                              iconSize: 18,
                              entries: widget.menuEntries(
                                context,
                                reactionMenuAt: () => quarkMenuAnchor(context),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // On a touch screen the row is the menu's only way in, so a screen
    // reader gets its actions here.
    final row = hasMenu && touchMenu
        ? Semantics(
            container: true,
            customSemanticsActions: {
              for (final entry in widget.menuEntries(context))
                CustomSemanticsAction(label: entry.label): ?entry.onSelected,
              if (onReact != null)
                const CustomSemanticsAction(label: 'Add reaction'):
                    _openContextMenu,
            },
            child: tinted,
          )
        : tinted;
    if (!mentionsSelf) return row;
    return Semantics(
      label: 'Mentions you',
      child: DecoratedBox(
        key: ValueKey('message_mention_${message.id}'),
        decoration: BoxDecoration(
          color: tokens.primary.withValues(alpha: 0.08),
          border: BorderDirectional(
            start: BorderSide(color: tokens.primary, width: 3),
          ),
        ),
        child: row,
      ),
    );
  }
}
