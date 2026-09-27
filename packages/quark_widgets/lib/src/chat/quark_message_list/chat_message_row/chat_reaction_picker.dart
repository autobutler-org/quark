import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../../theme/quark_tokens.dart';

/// The add-reaction button on a message, which opens a menu of [choices] and
/// fires [onPick] with the one chosen.
///
/// The menu is a `MenuAnchor`, which opens and closes without animating, so
/// there is no motion to reduce.
///
/// A part of `ChatMessageRow`, tested through `QuarkMessageList`.
///
/// Key prefixes: `message_react_<messageId>` on the button and
/// `message_react_<messageId>_<emoji>` on each menu entry.
class ChatReactionPicker extends StatelessWidget {
  /// Creates the button for message [messageId].
  const ChatReactionPicker({
    required this.messageId,
    required this.onPick,
    super.key,
  });

  /// The emoji the menu offers. Reactions are end-to-end encrypted, so the
  /// Quark can't restrict them; this short list is the only curation there
  /// is.
  static const List<String> choices = ['👍', '❤️', '😂', '😮', '😢', '🎉'];

  /// The message the button reacts to, which its keys carry.
  final String messageId;

  /// Called with the emoji chosen from the menu.
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return MenuAnchor(
      menuChildren: [
        for (final emoji in choices)
          MenuItemButton(
            key: ValueKey('message_react_${messageId}_$emoji'),
            onPressed: () => onPick(emoji),
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
      ],
      builder: (context, controller, _) => IconButton(
        key: ValueKey('message_react_$messageId'),
        tooltip: 'Add reaction',
        visualDensity: VisualDensity.compact,
        icon: Icon(
          QuarkIcons.add_reaction_outlined,
          size: 18,
          color: tokens.mutedForeground,
        ),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
