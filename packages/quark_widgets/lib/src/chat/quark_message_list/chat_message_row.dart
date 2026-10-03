import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../core/quark_menu_button.dart';
import '../../core/show_quark_menu.dart';
import '../../models/chat_message_item.dart';
import '../../models/quark_menu_entry.dart';
import '../../theme/quark_tokens.dart';
import 'chat_message_row/chat_message_body.dart';
import 'chat_message_row/chat_reaction_bar.dart';
import 'chat_message_row/chat_reaction_picker.dart';

/// One message a person sent, with the author's avatar, name and time above
/// it when it starts a group, or indented under the group's header when it
/// does not.
///
/// Draws the body of a text message, the "waiting for key" placeholder, or a
/// deleted message's tombstone, according to [ChatMessageItem.kind]. System
/// lines are a `ChatSystemLine` instead. A text message's reactions sit under
/// its body as a `ChatReactionBar`, and [onReact] adds a `ChatReactionPicker`
/// at the row's end as the quick way to react.
///
/// A text message has one menu, through `showQuarkMenu`: "Copy text" with
/// [onCopy], "Add reaction" with [onReact], which opens the picker's emoji as
/// a second menu in the same place, and "Delete" with [onDelete]. A null
/// callback leaves its entry out, and with all three null there is no menu. A
/// right-click opens it at the pointer, the three-dot button at the row's end
/// opens it for the keyboard, and with [longPressOpensMenu] a long press opens
/// it under the finger. `QuarkMessageList` turns the long press off on the
/// desktop platforms, where it makes the text selectable by dragging instead.
///
/// With [onOpenLink] set, the web addresses in a text message are links (see
/// `ChatMessageBody`), except in a message whose sender is unverified: an
/// address from someone who may not be who they claim is not put one tap
/// away.
///
/// A part of `QuarkMessageList`, tested through it.
///
/// Key prefixes: `message_body_<id>` on a text message's body,
/// `message_menu_<id>` on the menu button, `message_copy_<id>`,
/// `message_menu_react_<id>` and `message_delete_<id>` on the menu's entries,
/// `message_menu_react_<id>_<emoji>` on each emoji "Add reaction" offers, and
/// those of `ChatReactionBar` and `ChatReactionPicker`.
class ChatMessageRow extends StatelessWidget {
  /// Creates the row for [message].
  const ChatMessageRow({
    required this.message,
    required this.avatar,
    this.avatarSize = 32,
    this.onCopy,
    this.onDelete,
    this.onReact,
    this.onOpenLink,
    this.longPressOpensMenu = true,
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

  /// Called with a web address in the message's text when it is tapped. Null
  /// draws the text with no links, as an unverified message always is.
  final ValueChanged<Uri>? onOpenLink;

  /// Whether a long press opens the menu. False leaves the long press to
  /// whatever is above the row, such as a `SelectionArea`.
  final bool longPressOpensMenu;

  /// The menu's rows for a menu opened at [position], which is read when "Add
  /// reaction" opens its emoji there. Empty for anything but a text message.
  List<QuarkMenuEntry> menuEntries(
    BuildContext context,
    Offset Function() position,
  ) {
    final onCopy = this.onCopy;
    final onDelete = this.onDelete;
    final onReact = this.onReact;
    if (message.kind != ChatMessageKind.text) return const [];
    return [
      if (onCopy != null)
        QuarkMenuEntry(
          key: ValueKey('message_copy_${message.id}'),
          label: 'Copy text',
          icon: QuarkIcons.content_copy,
          onSelected: onCopy,
        ),
      if (onReact != null)
        QuarkMenuEntry(
          key: ValueKey('message_menu_react_${message.id}'),
          label: 'Add reaction',
          icon: QuarkIcons.add_reaction_outlined,
          onSelected: () {
            if (!context.mounted) return;
            showQuarkMenu(
              context,
              position: position(),
              entries: [
                for (final emoji in ChatReactionPicker.choices)
                  QuarkMenuEntry(
                    key: ValueKey('message_menu_react_${message.id}_$emoji'),
                    label: emoji,
                    onSelected: () => onReact(emoji),
                  ),
              ],
            );
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

  /// The time drawn beside the author's name, as `HH:mm`.
  static String timeOf(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final avatar = this.avatar;
    final onReact = this.onReact;
    final reacts = message.kind == ChatMessageKind.text;
    final hasMenu =
        reacts && (onCopy != null || onReact != null || onDelete != null);
    void openMenu(Offset position) => showQuarkMenu(
      context,
      position: position,
      entries: menuEntries(context, () => position),
    );
    final muted = TextStyle(
      color: tokens.mutedForeground,
      fontStyle: FontStyle.italic,
    );

    final body = switch (message.kind) {
      ChatMessageKind.waitingForKey => Row(
        children: [
          Icon(
            QuarkIcons.key_outlined,
            size: 16,
            color: tokens.mutedForeground,
          ),
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
      ChatMessageKind.text || ChatMessageKind.system => ChatMessageBody(
        key: ValueKey('message_body_${message.id}'),
        text: message.body,
        style: TextStyle(
          color: message.isUnverified ? tokens.warning : tokens.foreground,
        ),
        onOpenLink: reacts && !message.isUnverified ? onOpenLink : null,
      ),
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: hasMenu && longPressOpensMenu
          ? (details) => openMenu(details.globalPosition)
          : null,
      onSecondaryTapUp: hasMenu
          ? (details) => openMenu(details.globalPosition)
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
                          timeOf(message.sentAt),
                          style: TextStyle(
                            color: tokens.mutedForeground,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  body,
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
            if (reacts && onReact != null)
              ChatReactionPicker(messageId: message.id, onPick: onReact),
            if (hasMenu)
              // The same 48dp touch target as the picker beside it, so the two
              // glyphs share a center (#2605). The Builder makes the button
              // the anchor of "Add reaction".
              Builder(
                builder: (context) => QuarkMenuButton(
                  key: ValueKey('message_menu_${message.id}'),
                  tooltip: 'Message actions',
                  iconSize: 18,
                  entries: menuEntries(context, () => quarkMenuAnchor(context)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
