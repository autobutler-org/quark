/// What one question in a chat poll asks for, which decides how
/// `QuarkPollCard` lets a reader answer and `QuarkPollEditor` builds it.
///
/// The names are the `type` strings of a poll's payload.
enum ChatPollType {
  /// Pick one of the options, as radio buttons.
  single,

  /// Pick any of the options, as checkboxes.
  multiple,

  /// Write a free-text answer.
  text,

  /// Write a number.
  number,

  /// Pick a calendar day.
  date,

  /// Pick a step on a scale, from 1 up to the question's scale.
  rating;

  /// The smallest scale a rating question can offer.
  static const int minRating = 2;

  /// The largest scale a rating question can offer.
  static const int maxRating = 10;

  /// The scale a rating question starts with.
  static const int defaultRating = 5;

  /// Whether the question lists options the reader picks from.
  bool get hasOptions =>
      this == ChatPollType.single || this == ChatPollType.multiple;

  /// What the type is called on the poll form.
  String get label => switch (this) {
    ChatPollType.single => 'One choice',
    ChatPollType.multiple => 'Several choices',
    ChatPollType.text => 'Written answer',
    ChatPollType.number => 'Number',
    ChatPollType.date => 'Date',
    ChatPollType.rating => 'Rating',
  };
}
