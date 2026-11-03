import 'package:flutter/foundation.dart';

import 'chat_poll_answer.dart';
import 'chat_poll_type.dart';

/// A chat poll as `QuarkPollCard` draws it: its one question, its settings,
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
    this.responseCount = 0,
    this.myAnswer,
    this.isClosed = false,
    this.closesAt,
    this.allowChange = false,
    this.anonymous = false,
    this.resultsAfterClose = false,
    this.resultsVisible = true,
  });

  /// The question.
  final String prompt;

  /// What the question asks for.
  final ChatPollType type;

  /// The options of a `single` or `multiple` poll, in order. Empty for a
  /// `text` poll.
  final List<String> options;

  /// How many answers picked each of [options], index for index. A missing
  /// entry counts as zero.
  final List<int> counts;

  /// The written answers of a `text` poll that the reader may see, in the
  /// order to list them.
  final List<String> textAnswers;

  /// How many people have answered.
  final int responseCount;

  /// The reader's own answer, or null before they answer.
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatPollItem &&
          other.prompt == prompt &&
          other.type == type &&
          listEquals(other.options, options) &&
          listEquals(other.counts, counts) &&
          listEquals(other.textAnswers, textAnswers) &&
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
