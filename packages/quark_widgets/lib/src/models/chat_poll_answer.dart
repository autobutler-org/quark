import 'package:flutter/foundation.dart';

/// One reader's answer to a chat poll's question: the options they picked, by
/// index, or the text they wrote.
///
/// A `single` or `multiple` poll reads [choices] and a `text` poll reads
/// [text]; the other is left empty.
@immutable
class ChatPollAnswer {
  /// Creates an answer.
  const ChatPollAnswer({this.choices = const [], this.text = ''});

  /// The indices of the options picked, in ascending order.
  final List<int> choices;

  /// The free-text answer, untrimmed.
  final String text;

  /// Whether nothing is picked and no text is written, which is not an answer
  /// a poll accepts.
  bool get isEmpty => choices.isEmpty && text.trim().isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatPollAnswer &&
          listEquals(other.choices, choices) &&
          other.text == text;

  @override
  int get hashCode => Object.hash(Object.hashAll(choices), text);
}
