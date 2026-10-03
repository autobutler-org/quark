import 'package:flutter/material.dart';

import '../../../models/chat_reaction_item.dart';
import '../../../theme/quark_tokens.dart';

/// A message's reactions under its body: one chip per emoji with its count,
/// highlighted where the signed-in account reacted.
///
/// Tapping a chip fires [onToggle] with its emoji, which the caller reads as
/// "add mine" or "take mine back" from [ChatReactionItem.reactedByMe]. With
/// no [onToggle] the chips only show. Each chip answers taps across a 48dp
/// square around it, the minimum touch target (#2605), so a row of reactions
/// stands 48dp tall.
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
    VoidCallback? toggle(ChatReactionItem reaction) =>
        onToggle == null ? null : () => onToggle(reaction.emoji);
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
              // Excluding the child's semantics drops its tap too, so the node
              // carries its own, or a screen reader cannot press it (#2603).
              onTap: toggle(reaction),
              // The chip is drawn its own size; the 48dp square around it
              // takes the taps that miss it.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: toggle(reaction),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: kMinInteractiveDimension,
                    minHeight: kMinInteractiveDimension,
                  ),
                  child: Center(
                    widthFactor: 1,
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
                        onTap: toggle(reaction),
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
                ),
              ),
            ),
        ],
      ),
    );
  }
}
