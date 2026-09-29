import 'package:flutter/foundation.dart';

/// One emoji's reactions on a chat message, as the chat widgets draw them: the
/// emoji, how many people chose it, and whether the signed-in account is one
/// of them.
///
/// The caller groups the message's reactions by emoji; the widgets only draw
/// the result.
@immutable
class ChatReactionItem {
  /// Creates a reaction value.
  const ChatReactionItem({
    required this.emoji,
    required this.count,
    this.reactedByMe = false,
  });

  /// The emoji, already decrypted.
  final String emoji;

  /// How many reactions carry [emoji], at least one.
  final int count;

  /// Whether the signed-in account reacted with [emoji], which draws the
  /// chip highlighted and makes tapping it take the reaction back.
  final bool reactedByMe;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatReactionItem &&
          other.emoji == emoji &&
          other.count == count &&
          other.reactedByMe == reactedByMe;

  @override
  int get hashCode => Object.hash(emoji, count, reactedByMe);
}
