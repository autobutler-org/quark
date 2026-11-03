import 'package:flutter/foundation.dart';

import 'chat_poll_type.dart';

/// A poll as `QuarkPollEditor` edits it, before it is posted: the one
/// question and the four settings the Quark enforces.
@immutable
class ChatPollDraft {
  /// Creates a draft. A new poll starts with two blank options.
  const ChatPollDraft({
    this.prompt = '',
    this.type = ChatPollType.single,
    this.options = const ['', ''],
    this.closesAt,
    this.allowChange = true,
    this.anonymous = false,
    this.resultsAfterClose = false,
  });

  /// The question; blank until typed.
  final String prompt;

  /// What the question asks for.
  final ChatPollType type;

  /// The options as typed. Read only while [type] is not text, so switching
  /// to text and back keeps them.
  final List<String> options;

  /// When the poll closes on its own, or null for never.
  final DateTime? closesAt;

  /// Whether a reader may change their answer while the poll is open.
  final bool allowChange;

  /// Whether nobody, the author included, sees who gave which answer.
  final bool anonymous;

  /// Whether readers other than the author see results only once it closes.
  final bool resultsAfterClose;

  /// The options to post: the typed ones, trimmed, without the blank ones.
  List<String> get filledOptions => [
    for (final option in options)
      if (option.trim().isNotEmpty) option.trim(),
  ];

  /// Whether the draft can be posted: it has a question, and a choice poll
  /// has at least two options.
  bool get isComplete =>
      prompt.trim().isNotEmpty &&
      (type == ChatPollType.text || filledOptions.length >= 2);

  /// A copy with the given fields replaced. [clearClosesAt] makes the poll
  /// never close on its own.
  ChatPollDraft copyWith({
    String? prompt,
    ChatPollType? type,
    List<String>? options,
    DateTime? closesAt,
    bool clearClosesAt = false,
    bool? allowChange,
    bool? anonymous,
    bool? resultsAfterClose,
  }) => ChatPollDraft(
    prompt: prompt ?? this.prompt,
    type: type ?? this.type,
    options: options ?? this.options,
    closesAt: clearClosesAt ? null : closesAt ?? this.closesAt,
    allowChange: allowChange ?? this.allowChange,
    anonymous: anonymous ?? this.anonymous,
    resultsAfterClose: resultsAfterClose ?? this.resultsAfterClose,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatPollDraft &&
          other.prompt == prompt &&
          other.type == type &&
          listEquals(other.options, options) &&
          other.closesAt == closesAt &&
          other.allowChange == allowChange &&
          other.anonymous == anonymous &&
          other.resultsAfterClose == resultsAfterClose;

  @override
  int get hashCode => Object.hash(
    prompt,
    type,
    Object.hashAll(options),
    closesAt,
    allowChange,
    anonymous,
    resultsAfterClose,
  );
}
