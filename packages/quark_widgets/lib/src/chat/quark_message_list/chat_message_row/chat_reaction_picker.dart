import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../../theme/quark_tokens.dart';
import '../chat_emoji_picker.dart';

/// The add-reaction button on a message. It opens a menu of [choices] and a
/// "More emoji" entry, and fires [onPick] with the one chosen.
///
/// "More emoji" opens the searchable [ChatEmojiPicker], unless [pickMoreEmoji]
/// is set, in which case that is asked instead. Dismissing it does not call
/// [onPick].
///
/// The menu is a `MenuAnchor`, which opens and closes without animating, so
/// there is no motion to reduce. Opened from the keyboard, the menu moves
/// focus to its first emoji, so the arrow keys walk the emoji instead of
/// carrying focus on to the next message's buttons (#3257). Stateful only
/// for that emoji's [FocusNode].
///
/// A part of `ChatMessageRow`, tested through `QuarkMessageList`.
///
/// Key prefixes: `message_react_<messageId>` on the button,
/// `message_react_<messageId>_<emoji>` on each quick emoji, and
/// `message_react_<messageId>_more` on "More emoji".
class ChatReactionPicker extends StatefulWidget {
  /// Creates the button for message [messageId].
  const ChatReactionPicker({
    required this.messageId,
    required this.onPick,
    this.pickMoreEmoji,
    super.key,
  });

  /// The emoji the quick menu offers, one tap away. Anything else comes from
  /// [ChatEmojiPicker], or from [pickMoreEmoji] when the caller supplies one.
  static const List<String> choices = ['👍', '❤️', '😂', '😮', '😢', '🎉'];

  /// The message the button reacts to, which its keys carry.
  final String messageId;

  /// Called with the emoji chosen from the menu or the full picker.
  final ValueChanged<String> onPick;

  /// Asks for an emoji beyond [choices]. Null opens [ChatEmojiPicker]. A null
  /// result does not call [onPick].
  final Future<String?> Function(BuildContext context, String messageId)?
  pickMoreEmoji;

  @override
  State<ChatReactionPicker> createState() => _ChatReactionPickerState();
}

class _ChatReactionPickerState extends State<ChatReactionPicker> {
  final _first = FocusNode(debugLabel: 'ChatReactionPicker first emoji');

  @override
  void dispose() {
    _first.dispose();
    super.dispose();
  }

  /// A pointer opens the menu without focusing it, as every menu does; the
  /// keyboard needs focus in it to pick anything.
  void _onOpen() {
    if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_first.context != null) _first.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final messageId = widget.messageId;
    return MenuAnchor(
      onOpen: _onOpen,
      menuChildren: [
        for (final emoji in ChatReactionPicker.choices)
          MenuItemButton(
            key: ValueKey('message_react_${messageId}_$emoji'),
            focusNode: emoji == ChatReactionPicker.choices.first
                ? _first
                : null,
            onPressed: () => widget.onPick(emoji),
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
        MenuItemButton(
          key: ValueKey('message_react_${messageId}_more'),
          onPressed: () => requestMoreEmoji(
            context,
            messageId: messageId,
            onPick: widget.onPick,
            pickMore: widget.pickMoreEmoji,
          ),
          child: const Text('More emoji'),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        key: ValueKey('message_react_$messageId'),
        tooltip: 'Add reaction',
        icon: Icon(
          QuarkIcons.add_reaction_outlined,
          size: 18,
          color: tokens.secondaryForeground,
        ),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
