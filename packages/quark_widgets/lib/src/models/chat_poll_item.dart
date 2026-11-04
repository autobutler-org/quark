import 'package:flutter/foundation.dart';

import 'chat_poll_answer.dart';
import 'chat_poll_question_item.dart';
import 'chat_poll_type.dart';

/// A chat poll as `QuarkPollCard` draws it: its questions, its settings,
/// and the tally the caller counted.
///
/// The package's own view of a poll. Decrypting the question and the answers
/// and counting them is the caller's job; the card only draws the result.
@immutable
class ChatPollItem {
  /// Creates a poll value.
  const ChatPollItem({
    required this.prompt,
    this.type = ChatPollType.single,
    this.options = const [],
    this.counts = const [],
    this.textAnswers = const [],
    this.scale = ChatPollType.defaultRating,
    this.ratingCounts = const [],
    this.questions = const [],
    this.responseCount = 0,
    this.myAnswer,
    this.isClosed = false,
    this.closesAt,
    this.allowChange = false,
    this.anonymous = false,
    this.resultsAfterClose = false,
    this.resultsVisible = true,
  });

  /// The first question. A poll with several questions repeats it as
  /// [questions]'s first entry; the card draws [shownQuestions].
  final String prompt;

  /// What the first question asks for.
  final ChatPollType type;

  /// The options of a `single` or `multiple` poll, in order. Empty for a
  /// `text` poll.
  final List<String> options;

  /// How many answers picked each of [options], index for index. A missing
  /// entry counts as zero.
  final List<int> counts;

  /// The written answers of a `text` question, the numbers of a `number`
  /// question, or the `YYYY-MM-DD` days of a `date` question, for the first
  /// question, in the order to list them.
  final List<String> textAnswers;

  /// How many steps the first question offers when it is a rating.
  final int scale;

  /// How many answers gave each step of the first question when it is a
  /// rating. Index 0 is step 1.
  final List<int> ratingCounts;

  /// Every question, in order. Empty when the poll was built from the flat
  /// fields above, which are then its one question.
  final List<ChatPollQuestionItem> questions;

  /// How many people have answered.
  final int responseCount;

  /// The reader's own answer to the poll, or null before they answer. A poll
  /// with one question uses the flat fields; one with several carries them
  /// in [ChatPollAnswer.parts].
  final ChatPollAnswer? myAnswer;

  /// Whether the poll takes no more answers: its author closed it, or
  /// [closesAt] has passed.
  final bool isClosed;

  /// When the poll closes on its own, or null for never.
  final DateTime? closesAt;

  /// Whether a reader may change their answer while the poll is open.
  final bool allowChange;

  /// Whether nobody, the author included, sees who gave which answer.
  final bool anonymous;

  /// Whether readers other than the author see the results only once the
  /// poll closes.
  final bool resultsAfterClose;

  /// Whether the reader may see the tally now. False while a
  /// [resultsAfterClose] poll is open and the reader is not its author, which
  /// draws a placeholder in place of the results.
  final bool resultsVisible;

  /// The count for the option at [index], zero when [counts] has none.
  int countAt(int index) => index < counts.length ? counts[index] : 0;

  /// The questions the card draws. [questions] when it is set, and otherwise
  /// the flat fields as the one question.
  List<ChatPollQuestionItem> get shownQuestions => questions.isNotEmpty
      ? questions
      : [
          ChatPollQuestionItem(
            prompt: prompt,
            type: type,
            options: options,
            counts: counts,
            textAnswers: textAnswers,
            scale: scale,
            ratingCounts: ratingCounts,
            myAnswer: myAnswer != null && myAnswer!.parts.isNotEmpty
                ? myAnswer!.parts.first
                : myAnswer,
          ),
        ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatPollItem &&
          other.prompt == prompt &&
          other.type == type &&
          listEquals(other.options, options) &&
          listEquals(other.counts, counts) &&
          listEquals(other.textAnswers, textAnswers) &&
          other.scale == scale &&
          listEquals(other.ratingCounts, ratingCounts) &&
          listEquals(other.questions, questions) &&
          other.responseCount == responseCount &&
          other.myAnswer == myAnswer &&
          other.isClosed == isClosed &&
          other.closesAt == closesAt &&
          other.allowChange == allowChange &&
          other.anonymous == anonymous &&
          other.resultsAfterClose == resultsAfterClose &&
          other.resultsVisible == resultsVisible;

  @override
  int get hashCode => Object.hash(
    prompt,
    type,
    Object.hashAll(options),
    Object.hashAll(counts),
    Object.hashAll(textAnswers),
    scale,
    Object.hashAll(ratingCounts),
    Object.hashAll(questions),
    responseCount,
    myAnswer,
    isClosed,
    closesAt,
    allowChange,
    anonymous,
    resultsAfterClose,
    resultsVisible,
  );
}
