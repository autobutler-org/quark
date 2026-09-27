import 'package:flutter/material.dart';

import '../../../models/chat_reaction_item.dart';
import '../../../theme/quark_tokens.dart';

/// A message's reactions under its body: one chip per emoji with its count,
/// highlighted where the signed-in account reacted.
///
/// Tapping a chip fires [onToggle] with its emoji, which the caller reads as
/// "add mine" or "take mine back" from [ChatReactionItem.reactedByMe]. With
/// no [onToggle] the chips only show.
///
/// A part of `ChatMessageRow`, tested through `QuarkMessageList`.
///
/// Key prefix: `message_reaction_<messageId>_<emoji>` on each chip.
class ChatReactionBar extends StatelessWidget {
  /// Creates the chips for [reactions] on message [messageId].
  const ChatReactionBar({
    required this.messageId,
    required this.reactions,
    this.onToggle,
    super.key,
  });

  /// The message the reactions are on, which the chips' keys carry.
  final String messageId;

  /// The reactions, one per emoji, in order.
  final List<ChatReactionItem> reactions;

  /// Called with a chip's emoji when it is tapped. Null leaves the chips
  /// inert.
  final ValueChanged<String>? onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final onToggle = this.onToggle;
    return Padding(
      padding: EdgeInsets.only(top: tokens.spacingXs),
      child: Wrap(
        spacing: tokens.spacingXs,
        runSpacing: tokens.spacingXs,
        children: [
          for (final reaction in reactions)
            Semantics(
              button: onToggle != null,
              selected: reaction.reactedByMe,
              label:
                  '${reaction.emoji} ${reaction.count}'
                  '${reaction.reactedByMe ? ', including you' : ''}',
              excludeSemantics: true,
              child: Material(
                key: ValueKey(
                  'message_reaction_${messageId}_${reaction.emoji}',
                ),
                color: reaction.reactedByMe
                    ? tokens.primary.withValues(alpha: 0.16)
                    : tokens.card,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: reaction.reactedByMe
                        ? tokens.primary
                        : tokens.border,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onToggle == null
                      ? null
                      : () => onToggle(reaction.emoji),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: tokens.spacingSm,
                      vertical: 2,
                    ),
                    child: Text(
                      '${reaction.emoji} ${reaction.count}',
                      style: TextStyle(
                        fontSize: 13,
                        color: reaction.reactedByMe
                            ? tokens.primary
                            : tokens.foreground,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
