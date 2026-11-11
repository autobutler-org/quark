import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../../theme/quark_tokens.dart';
import 'chat_reaction_picker.dart';

/// The row of emoji above a message in `ChatMessageContextMenu`: each of
/// [ChatReactionPicker.choices] one tap away, and "More emoji" for any
/// other, on a pill of `QuarkTokens.card`.
///
/// A tap on an emoji fires [onReact] with it, and "More emoji" fires
/// [onMoreEmoji]; the menu closes before either runs. Each is a 48dp button.
/// Wider than the screen, as at a large text size, the row scrolls sideways.
///
/// A part of `ChatMessageRow`, tested through `QuarkMessageList`.
///
/// Key prefixes: `message_menu_react_<messageId>_<emoji>` on each emoji and
/// `message_menu_react_<messageId>_more` on "More emoji", the keys the
/// pointer menu's "Add reaction" uses.
class ChatQuickReactionBar extends StatelessWidget {
  /// Creates the bar for message [messageId].
  const ChatQuickReactionBar({
    required this.messageId,
    required this.onReact,
    this.onMoreEmoji,
    super.key,
  });

  /// The message the bar reacts to, which its keys carry.
  final String messageId;

  /// Called with the emoji tapped.
  final ValueChanged<String> onReact;

  /// Called when "More emoji" is tapped. Null leaves it out.
  final VoidCallback? onMoreEmoji;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final onMoreEmoji = this.onMoreEmoji;
    return Material(
      color: tokens.card,
      shape: StadiumBorder(side: BorderSide(color: tokens.border)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final emoji in ChatReactionPicker.choices)
              IconButton(
                key: ValueKey('message_menu_react_${messageId}_$emoji'),
                onPressed: () => onReact(emoji),
                icon: Text(emoji, style: const TextStyle(fontSize: 22)),
              ),
            if (onMoreEmoji != null)
              IconButton(
                key: ValueKey('message_menu_react_${messageId}_more'),
                tooltip: 'More emoji',
                onPressed: onMoreEmoji,
                icon: Icon(
                  QuarkIcons.search,
                  size: 20,
                  color: tokens.secondaryForeground,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
