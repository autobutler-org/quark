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

  /// When it stops taking answers on its own, or null for never. The Quark
  /// refuses a time in the past or more than a year after the post.
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

/// A poll's questions, as its message's plaintext carries them (#3894):
///
/// `{"quark":"poll/1","questions":[{"id":"q1","type":"single","prompt":"…","options":["…"]}]}`
///
/// [prompt], [type], [options] and [scale] are the first question. [more]
/// holds the rest. The marker is one no typed message produces, so [parse]
/// tells a poll from text. An answer's plaintext is keyed by question id:
/// `{"q1":[0,2]}` for choices, `{"q1":"text"}` for text, `{"q1":3}` for a
/// number or a rating, and `{"q1":"2026-11-04"}` for a date
/// ([encodeAnswer], [decodeAnswer]).
final class ChatPollQuestion {
  /// Builds a question. [more] are the questions after this one; their own
  /// [more] is not read.
  const ChatPollQuestion({
    required this.prompt,
    this.id = 'q1',
    this.type = ChatPollType.single,
    this.options = const [],
    this.scale = ChatPollType.defaultRating,
    this.more = const [],
  });

  /// The questions from [draft], trimmed, a choice question's blank options
  /// dropped. Ids are `q1`, `q2`, and so on, in the draft's order.
  factory ChatPollQuestion.fromDraft(ChatPollDraft draft) {
    final built = [
      for (final (index, question) in draft.questions.indexed)
        ChatPollQuestion._from(index, question),
    ];
    final first = built.first;
    return ChatPollQuestion(
      id: first.id,
      prompt: first.prompt,
      type: first.type,
      options: first.options,
      scale: first.scale,
      more: List.unmodifiable(built.skip(1)),
    );
  }

  /// Question [index] of a draft, id `q<index+1>`.
  ChatPollQuestion._from(int index, ChatPollQuestionDraft question)
    : id = 'q${index + 1}',
      prompt = question.prompt.trim(),
      type = question.type,
      options = question.type.hasOptions
          ? List.unmodifiable(question.filledOptions)
          : const [],
      scale = question.type == ChatPollType.rating
          ? question.scale
          : ChatPollType.defaultRating,
      more = const [];

  /// The payload's marker and version.
  static const marker = 'poll/1';

  /// The first question's id within the poll; what its answer is keyed by.
  final String id;

  /// What the first question asks for.
  final ChatPollType type;

  /// The first question.
  final String prompt;

  /// The first question's options, in order; empty unless it is a choice.
  final List<String> options;

  /// How many steps the first question offers when it is a rating.
  final int scale;

  /// The questions after the first, in order.
  final List<ChatPollQuestion> more;

  /// Every question, the first one first.
  List<ChatPollQuestion> get questions => [this, ...more];

  /// The poll message's plaintext.
  String toPayload() => jsonEncode({
    'quark': marker,
    'questions': [
      for (final question in questions)
        {
          'id': question.id,
          'type': question.type.name,
          'prompt': question.prompt,
          if (question.type.hasOptions) 'options': question.options,
          if (question.type == ChatPollType.rating) 'scale': question.scale,
        },
    ],
  });

  /// The questions [text] carries, or null when it isn't a poll payload: no
  /// questions, a repeated id, an unknown type, a choice with fewer than two
  /// options, a rating whose scale is outside
  /// [ChatPollType.minRating]..[ChatPollType.maxRating], or a blank prompt.
  static ChatPollQuestion? parse(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map || json['quark'] != marker) return null;
      final raw = json['questions'] as List;
      if (raw.isEmpty) return null;
      final questions = <ChatPollQuestion>[];
      final ids = <String>{};
      for (final item in raw) {
        final q = item as Map;
        final id = q['id'] as String;
        if (id.isEmpty || !ids.add(id)) return null;
        final type = ChatPollType.values.byName(q['type'] as String);
        final prompt = q['prompt'] as String;
        if (prompt.trim().isEmpty) return null;
        final options = [
          for (final o in q['options'] as List? ?? const []) o as String,
        ];
        if (type.hasOptions && options.length < 2) return null;
        final scale = _scale(q['scale']);
        if (type == ChatPollType.rating &&
            (scale < ChatPollType.minRating ||
                scale > ChatPollType.maxRating)) {
          return null;
        }
        questions.add(
          ChatPollQuestion(
            id: id,
            type: type,
            prompt: prompt,
            options: type.hasOptions ? List.unmodifiable(options) : const [],
            scale: type == ChatPollType.rating
                ? scale
                : ChatPollType.defaultRating,
          ),
        );
      }
      final first = questions.first;
      return ChatPollQuestion(
        id: first.id,
        type: first.type,
        prompt: first.prompt,
        options: first.options,
        scale: first.scale,
        more: List.unmodifiable(questions.skip(1)),
      );
    } on Object {
      return null;
    }
  }

  /// [answer]'s plaintext, before padding, one entry per question.
  String encodeAnswer(ChatPollAnswer answer) {
    final parts = questions.length == 1 ? [answer] : answer.parts;
    return jsonEncode({
      for (final (index, question) in questions.indexed)
        question.id: question._jsonValue(parts[index]),
    });
  }

  /// The answer [text] carries, or null when it doesn't fit these questions:
  /// a value missing or of the wrong kind, a choice out of range or repeated,
  /// more than one for a single choice, a rating outside the scale, or a
  /// date that is not a real day. A poll with one question returns that
  /// answer's fields; one with several returns them in [ChatPollAnswer.parts].
  ChatPollAnswer? decodeAnswer(String text) {
    try {
      final json = jsonDecode(text) as Map;
      final parts = <ChatPollAnswer>[];
      for (final question in questions) {
        final part = question._decodePart(json[question.id]);
        if (part == null) return null;
        parts.add(part);
      }
      return parts.length == 1
          ? parts.single
          : ChatPollAnswer(parts: List.unmodifiable(parts));
    } on Object {
      return null;
    }
  }

  /// [raw] as a rating scale. Absent means [ChatPollType.defaultRating].
  static int _scale(Object? raw) {
    if (raw == null) return ChatPollType.defaultRating;
    if (raw is! num || raw != raw.roundToDouble()) {
      throw const FormatException('a rating scale is a whole number');
    }
    return raw.toInt();
  }

  Object? _jsonValue(ChatPollAnswer answer) => switch (type) {
    ChatPollType.single || ChatPollType.multiple => answer.choices,
    ChatPollType.text => answer.text.trim(),
    ChatPollType.number => ChatPollAnswer.encodeNumber(answer.number),
    ChatPollType.date => answer.date,
    ChatPollType.rating => answer.rating,
  };

  ChatPollAnswer? _decodePart(Object? value) {
    switch (type) {
      case ChatPollType.text:
        if (value is! String || value.trim().isEmpty) return null;
        return ChatPollAnswer(text: value);
      case ChatPollType.number:
        if (value is! num) return null;
        final text = ChatPollAnswer.numberText(value);
        return text == null ? null : ChatPollAnswer(number: text);
      case ChatPollType.date:
        if (value is! String || ChatPollAnswer.parseDate(value) == null) {
          return null;
        }
        return ChatPollAnswer(date: value);
      case ChatPollType.rating:
        if (value is! num || value != value.roundToDouble()) return null;
        final rating = value.toInt();
        if (rating < 1 || rating > scale) return null;
        return ChatPollAnswer(rating: rating);
      case ChatPollType.single || ChatPollType.multiple:
        if (value is! List) return null;
        final choices = [for (final c in value) c as int]..sort();
        final valid =
            choices.isNotEmpty &&
            choices.toSet().length == choices.length &&
            choices.first >= 0 &&
            choices.last < options.length &&
            (type == ChatPollType.multiple || choices.length == 1);
        return valid
            ? ChatPollAnswer(choices: List.unmodifiable(choices))
            : null;
    }
  }
}
