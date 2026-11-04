import 'package:flutter/foundation.dart';

import 'chat_poll_answer.dart';
import 'chat_poll_type.dart';

/// One question of a chat poll as `QuarkPollCard` draws it, with the tally
/// the caller counted for it.
@immutable
class ChatPollQuestionItem {
  /// Creates a question value.
  const ChatPollQuestionItem({
    required this.prompt,
    this.type = ChatPollType.single,
    this.options = const [],
    this.counts = const [],
    this.textAnswers = const [],
    this.scale = ChatPollType.defaultRating,
    this.ratingCounts = const [],
    this.myAnswer,
  });

  /// The question.
  final String prompt;

  /// What the question asks for.
  final ChatPollType type;

  /// The options of a `single` or `multiple` question, in order.
  final List<String> options;

  /// How many answers picked each of [options], index for index. A missing
  /// entry counts as zero.
  final List<int> counts;

  /// The written answers of a `text` question, the numbers of a `number`
  /// question, or the `YYYY-MM-DD` days of a `date` question, in the order
  /// to list them.
  final List<String> textAnswers;

  /// How many steps a `rating` question offers. The answer is from 1 to this.
  final int scale;

  /// How many answers gave each step of a `rating` question. Index 0 is
  /// step 1. A missing entry counts as zero.
  final List<int> ratingCounts;

  /// The reader's own answer to this question, or null before they answer.
  final ChatPollAnswer? myAnswer;

  /// The count for the option at [index], zero when [counts] has none.
  int countAt(int index) => index < counts.length ? counts[index] : 0;

  /// How many answers gave rating [step], zero when [ratingCounts] has none.
  int ratingAt(int step) =>
      step >= 1 && step <= ratingCounts.length ? ratingCounts[step - 1] : 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatPollQuestionItem &&
          other.prompt == prompt &&
          other.type == type &&
          listEquals(other.options, options) &&
          listEquals(other.counts, counts) &&
          listEquals(other.textAnswers, textAnswers) &&
          other.scale == scale &&
          listEquals(other.ratingCounts, ratingCounts) &&
          other.myAnswer == myAnswer;

  @override
  int get hashCode => Object.hash(
    prompt,
    type,
    Object.hashAll(options),
    Object.hashAll(counts),
    Object.hashAll(textAnswers),
    scale,
    Object.hashAll(ratingCounts),
    myAnswer,
  );
}
