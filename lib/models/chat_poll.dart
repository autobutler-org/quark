import 'dart:convert';
import 'dart:typed_data';

import 'package:quark_widgets/quark_widgets.dart';

/// A poll message's settings and state as the Quark stores them (#3893),
/// beside the message whose ciphertext holds the question.
///
/// The Quark enforces [closesAt], [allowChange], [anonymous] and
/// [resultsAfterClose]; [answers] are the ones this account may see, still
/// encrypted. Posting sends only the four settings ([settingsJson]).
class ChatPoll {
  /// Builds a poll explicitly; posting and tests use it.
  const ChatPoll({
    this.closesAt,
    this.allowChange = false,
    this.anonymous = false,
    this.resultsAfterClose = false,
    this.closed = false,
    this.answers = const [],
  });

  /// When it stops taking answers on its own, or null for never.
  final DateTime? closesAt;

  /// Whether an account may replace its answer.
  final bool allowChange;

  /// Whether answers are served without the account that gave them.
  final bool anonymous;

  /// Whether only the author sees every answer until it closes.
  final bool resultsAfterClose;

  /// Whether the Quark said it takes no more answers: its author closed it,
  /// or [closesAt] had passed when it answered.
  final bool closed;

  /// The answers this account may see. A poll that names respondents lists
  /// them oldest first; an anonymous one lists them in an order that is not
  /// arrival order.
  final List<ChatPollResponse> answers;

  /// Whether it takes no more answers at [now]: [closed], or [closesAt] has
  /// passed since the Quark said so.
  bool isClosedAt(DateTime now) =>
      closed || (closesAt != null && !now.isBefore(closesAt!));

  /// This poll with [closed] and [answers] replaced.
  ChatPoll copyWith({bool? closed, List<ChatPollResponse>? answers}) =>
      ChatPoll(
        closesAt: closesAt,
        allowChange: allowChange,
        anonymous: anonymous,
        resultsAfterClose: resultsAfterClose,
        closed: closed ?? this.closed,
        answers: answers == null ? this.answers : List.unmodifiable(answers),
      );

  /// The `poll` object a post carries.
  Map<String, Object> settingsJson() => {
    'closesAt': ?closesAt?.toUtc().toIso8601String(),
    'allowChange': allowChange,
    'anonymous': anonymous,
    'resultsAfterClose': resultsAfterClose,
  };

  /// Reads a message's `poll` object, or a close's answer.
  factory ChatPoll.fromJson(Map<String, dynamic> json) {
    final closesAt = json['closesAt'] as String?;
    return ChatPoll(
      closesAt: closesAt == null ? null : DateTime.parse(closesAt),
      allowChange: json['allowChange'] as bool? ?? false,
      anonymous: json['anonymous'] as bool? ?? false,
      resultsAfterClose: json['resultsAfterClose'] as bool? ?? false,
      closed: json['closed'] as bool? ?? false,
      answers: List.unmodifiable([
        for (final a in json['answers'] as List? ?? const [])
          ChatPollResponse.fromJson(a as Map<String, dynamic>),
      ]),
    );
  }
}

/// One stored answer to a poll (#3893): who gave it, unless the poll is
/// anonymous, and what they chose as ciphertext the Quark can't open.
///
/// [ciphertext] is `nonce || XChaCha20-Poly1305 output` of the answer padded
/// to `ChatCrypto.pollAnswerPlaintextBytes`, bound to the channel, key
/// version, poll and, unless the poll is anonymous, the account
/// (`ChatCrypto.pollAnswerAad`).
class ChatPollResponse {
  /// Builds an answer explicitly; tests use it.
  const ChatPollResponse({
    required this.id,
    required this.messageId,
    required this.keyVersion,
    required this.ciphertext,
    this.userId,
    this.mine = false,
  });

  /// Stable for one account's answer on this poll, including when they change
  /// it. On an anonymous poll it is not the stored row id and does not follow
  /// arrival order.
  final int id;

  /// The poll message answered.
  final int messageId;

  /// Who answered, null on an anonymous poll.
  final int? userId;

  /// Whether this account gave it. Never set on an event.
  final bool mine;

  /// The channel key version it was encrypted under.
  final int keyVersion;

  /// The encrypted, padded answer.
  final Uint8List ciphertext;

  /// This answer marked as this account's.
  ChatPollResponse asMine() => ChatPollResponse(
    id: id,
    messageId: messageId,
    keyVersion: keyVersion,
    ciphertext: ciphertext,
    userId: userId,
    mine: true,
  );

  /// Reads one answer as the API or a `chat_poll_answer_changed` event sends
  /// it. An anonymous poll's `chat_poll_answers_changed` event carries no
  /// answer; the list is read again.
  factory ChatPollResponse.fromJson(Map<String, dynamic> json) =>
      ChatPollResponse(
        id: (json['id'] as num).toInt(),
        messageId: (json['messageId'] as num).toInt(),
        userId: (json['userId'] as num?)?.toInt(),
        mine: json['mine'] as bool? ?? false,
        keyVersion: (json['keyVersion'] as num).toInt(),
        ciphertext: base64Decode(json['ciphertext'] as String),
      );
}

/// A [ChatPollResponse] with what it decrypted to, when it opened and reads
/// as an answer to its question.
final class ChatOpenPollAnswer {
  /// Wraps [response] with its [answer].
  const ChatOpenPollAnswer({required this.response, this.answer});

  /// The stored answer.
  final ChatPollResponse response;

  /// The choices or text, or null while its key hasn't arrived, when it
  /// won't open, or when it doesn't fit the question.
  final ChatPollAnswer? answer;
}

/// A poll's one question, as its message's plaintext carries it (#3894):
///
/// `{"quark":"poll/1","questions":[{"id":"q1","type":"single","prompt":"…","options":["…"]}]}`
///
/// The marker is one no typed message produces, so [parse] tells a poll from
/// text. An answer's plaintext is `{"q1":[0,2]}` or `{"q1":"text"}`
/// ([encodeAnswer], [decodeAnswer]).
final class ChatPollQuestion {
  /// Builds a question.
  const ChatPollQuestion({
    required this.prompt,
    this.id = 'q1',
    this.type = ChatPollType.single,
    this.options = const [],
  });

  /// The question from [draft], trimmed, its blank options dropped.
  factory ChatPollQuestion.fromDraft(ChatPollDraft draft) => ChatPollQuestion(
    prompt: draft.prompt.trim(),
    type: draft.type,
    options: draft.type == ChatPollType.text ? const [] : draft.filledOptions,
  );

  /// The payload's marker and version.
  static const marker = 'poll/1';

  /// The question's id within the poll; what an answer is keyed by.
  final String id;

  /// What it asks for.
  final ChatPollType type;

  /// The question.
  final String prompt;

  /// A choice poll's options, in order; empty for a text poll.
  final List<String> options;

  /// The poll message's plaintext.
  String toPayload() => jsonEncode({
    'quark': marker,
    'questions': [
      {
        'id': id,
        'type': type.name,
        'prompt': prompt,
        if (type != ChatPollType.text) 'options': options,
      },
    ],
  });

  /// The question [text] carries, or null when it isn't a poll payload.
  static ChatPollQuestion? parse(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map || json['quark'] != marker) return null;
      final q = (json['questions'] as List).first as Map;
      final type = ChatPollType.values.byName(q['type'] as String);
      final options = [
        for (final o in q['options'] as List? ?? const []) o as String,
      ];
      if (type != ChatPollType.text && options.length < 2) return null;
      return ChatPollQuestion(
        id: q['id'] as String,
        type: type,
        prompt: q['prompt'] as String,
        options: List.unmodifiable(options),
      );
    } on Object {
      return null;
    }
  }

  /// [answer]'s plaintext, before padding: its choices, or its text trimmed.
  String encodeAnswer(ChatPollAnswer answer) => jsonEncode({
    id: type == ChatPollType.text ? answer.text.trim() : answer.choices,
  });

  /// The answer [text] carries, or null when it doesn't fit this question: a
  /// choice out of range or repeated, more than one for a single choice, or
  /// none at all.
  ChatPollAnswer? decodeAnswer(String text) {
    try {
      final value = (jsonDecode(text) as Map)[id];
      if (type == ChatPollType.text) {
        final written = value as String;
        return written.trim().isEmpty ? null : ChatPollAnswer(text: written);
      }
      final choices = [for (final c in value as List) c as int]..sort();
      final valid =
          choices.isNotEmpty &&
          choices.toSet().length == choices.length &&
          choices.first >= 0 &&
          choices.last < options.length &&
          (type == ChatPollType.multiple || choices.length == 1);
      return valid ? ChatPollAnswer(choices: List.unmodifiable(choices)) : null;
    } on Object {
      return null;
    }
  }
}
