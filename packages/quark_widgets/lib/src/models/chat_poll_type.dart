/// What a chat poll's one question asks for, which decides how
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
}
