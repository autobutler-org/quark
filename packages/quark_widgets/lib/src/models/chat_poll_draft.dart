import 'package:flutter/foundation.dart';

import 'chat_poll_type.dart';

/// One question of a poll as `QuarkPollEditor` edits it, before it is posted.
@immutable
class ChatPollQuestionDraft {
  /// Creates a question. A choice question starts with two blank options.
  const ChatPollQuestionDraft({
    this.prompt = '',
    this.type = ChatPollType.single,
    this.options = const ['', ''],
    this.scale = ChatPollType.defaultRating,
  });

  /// The question; blank until typed.
  final String prompt;

  /// What the question asks for.
  final ChatPollType type;

  /// The options as typed. Read only while [type] has options, so switching
  /// away and back keeps them.
  final List<String> options;

  /// How many steps a rating question offers.
  final int scale;

  /// The options to post: the typed ones, trimmed, without the blank ones.
  List<String> get filledOptions => [
    for (final option in options)
      if (option.trim().isNotEmpty) option.trim(),
  ];

  /// Whether this question can be posted.
  bool get isComplete =>
      prompt.trim().isNotEmpty &&
      switch (type) {
        ChatPollType.single ||
        ChatPollType.multiple => filledOptions.length >= 2,
        ChatPollType.rating =>
          scale >= ChatPollType.minRating && scale <= ChatPollType.maxRating,
        ChatPollType.text || ChatPollType.number || ChatPollType.date => true,
      };

  /// A copy with the given fields replaced.
  ChatPollQuestionDraft copyWith({
    String? prompt,
    ChatPollType? type,
    List<String>? options,
    int? scale,
  }) => ChatPollQuestionDraft(
    prompt: prompt ?? this.prompt,
    type: type ?? this.type,
    options: options ?? this.options,
    scale: scale ?? this.scale,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatPollQuestionDraft &&
          other.prompt == prompt &&
          other.type == type &&
          listEquals(other.options, options) &&
          other.scale == scale;

  @override
  int get hashCode => Object.hash(prompt, type, Object.hashAll(options), scale);
}

/// A poll as `QuarkPollEditor` edits it, before it is posted: its questions
/// and the four settings the Quark enforces.
///
/// [prompt], [type], [options] and [scale] are the first question. [more]
/// holds the questions after it, so a poll posted today with one question
/// is built the same way as before.
@immutable
class ChatPollDraft {
  /// Creates a draft. A new poll starts with one choice question of two
  /// blank options.
  const ChatPollDraft({
    this.prompt = '',
    this.type = ChatPollType.single,
    this.options = const ['', ''],
    this.scale = ChatPollType.defaultRating,
    this.more = const [],
    this.closesAt,
    this.allowChange = true,
    this.anonymous = false,
    this.resultsAfterClose = false,
  });

  /// The first question; blank until typed.
  final String prompt;

  /// What the first question asks for.
  final ChatPollType type;

  /// The first question's options as typed. Read only while [type] has
  /// options, so switching away and back keeps them.
  final List<String> options;

  /// How many steps the first question offers when it is a rating.
  final int scale;

  /// The questions after the first, in order.
  final List<ChatPollQuestionDraft> more;

  /// When the poll closes on its own, or null for never.
  final DateTime? closesAt;

  /// Whether a reader may change their answer while the poll is open.
  final bool allowChange;

  /// Whether nobody, the author included, sees who gave which answer.
  final bool anonymous;

  /// Whether readers other than the author see results only once it closes.
  final bool resultsAfterClose;

  /// Every question, the first one first.
  List<ChatPollQuestionDraft> get questions => [
    ChatPollQuestionDraft(
      prompt: prompt,
      type: type,
      options: options,
      scale: scale,
    ),
    ...more,
  ];

  /// The first question's options to post: the typed ones, trimmed, without
  /// the blank ones.
  List<String> get filledOptions => questions.first.filledOptions;

  /// Whether the draft can be posted: every question can.
  bool get isComplete => questions.every((question) => question.isComplete);

  /// A copy with the given fields replaced. [questions] replaces the whole
  /// list, the first one into [prompt] and the rest into [more].
  /// [clearClosesAt] makes the poll never close on its own.
  ChatPollDraft copyWith({
    String? prompt,
    ChatPollType? type,
    List<String>? options,
    int? scale,
    List<ChatPollQuestionDraft>? questions,
    DateTime? closesAt,
    bool clearClosesAt = false,
    bool? allowChange,
    bool? anonymous,
    bool? resultsAfterClose,
  }) {
    final first = questions?.first;
    return ChatPollDraft(
      prompt: first?.prompt ?? prompt ?? this.prompt,
      type: first?.type ?? type ?? this.type,
      options: first?.options ?? options ?? this.options,
      scale: first?.scale ?? scale ?? this.scale,
      more: questions == null ? more : List.unmodifiable(questions.skip(1)),
      closesAt: clearClosesAt ? null : closesAt ?? this.closesAt,
      allowChange: allowChange ?? this.allowChange,
      anonymous: anonymous ?? this.anonymous,
      resultsAfterClose: resultsAfterClose ?? this.resultsAfterClose,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatPollDraft &&
          other.prompt == prompt &&
          other.type == type &&
          listEquals(other.options, options) &&
          other.scale == scale &&
          listEquals(other.more, more) &&
          other.closesAt == closesAt &&
          other.allowChange == allowChange &&
          other.anonymous == anonymous &&
          other.resultsAfterClose == resultsAfterClose;

  @override
  int get hashCode => Object.hash(
    prompt,
    type,
    Object.hashAll(options),
    scale,
    Object.hashAll(more),
    closesAt,
    allowChange,
    anonymous,
    resultsAfterClose,
  );
}
