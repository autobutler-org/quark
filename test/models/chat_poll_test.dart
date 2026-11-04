import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/chat_poll.dart';
import 'package:quark_widgets/quark_widgets.dart';

void main() {
  const choice = ChatPollQuestion(prompt: 'Which?', options: ['A', 'B', 'C']);

  test('a one-question poll keeps the payload it has always had', () {
    final parsed = ChatPollQuestion.parse(choice.toPayload());
    expect(parsed?.questions, hasLength(1));
    expect(parsed?.type, ChatPollType.single);
    expect(
      choice.encodeAnswer(const ChatPollAnswer(choices: [2])),
      '{"q1":[2]}',
    );
    expect(
      choice.decodeAnswer('{"q1":[2]}'),
      const ChatPollAnswer(choices: [2]),
    );
    final several = ChatPollQuestion(
      prompt: 'Colors?',
      type: ChatPollType.multiple,
      options: choice.options,
    );
    expect(
      several.decodeAnswer('{"q1":[2,0]}'),
      const ChatPollAnswer(choices: [0, 2]),
    );
    expect(
      const ChatPollQuestion(
        prompt: 'Why?',
        type: ChatPollType.text,
      ).encodeAnswer(const ChatPollAnswer(text: '  hi  ')),
      '{"q1":"hi"}',
    );
  });

  test('number, date and rating round-trip, and a bad value does not', () {
    final poll = ChatPollQuestion.parse(
      jsonEncode({
        'quark': 'poll/1',
        'questions': [
          {'id': 'q1', 'type': 'number', 'prompt': 'How many?'},
          {'id': 'q2', 'type': 'date', 'prompt': 'When?'},
          {'id': 'q3', 'type': 'rating', 'prompt': 'How was it?', 'scale': 5},
        ],
      }),
    );
    expect(poll, isNotNull);
    final answer = const ChatPollAnswer(
      parts: [
        ChatPollAnswer(number: '4'),
        ChatPollAnswer(date: '2026-11-08'),
        ChatPollAnswer(rating: 4),
      ],
    );
    expect(poll!.decodeAnswer(poll.encodeAnswer(answer)), answer);
    expect(poll.decodeAnswer('{"q1":4,"q2":"2026-02-31","q3":4}'), isNull);
    expect(poll.decodeAnswer('{"q1":4,"q2":"2026-11-08","q3":6}'), isNull);
    expect(poll.decodeAnswer('{"q1":"4","q2":"2026-11-08","q3":4}'), isNull);
  });

  test('a rating without a scale is 5, and a bad poll does not parse', () {
    final implied = ChatPollQuestion.parse(
      '{"quark":"poll/1","questions":[{"id":"q1","type":"rating","prompt":"Rate"}]}',
    );
    expect(implied?.scale, 5);
    expect(
      ChatPollQuestion.parse(
        '{"quark":"poll/1","questions":[{"id":"q1","type":"rating","prompt":"Rate","scale":1}]}',
      ),
      isNull,
    );
    expect(
      ChatPollQuestion.parse(
        '{"quark":"poll/1","questions":[{"id":"q1","type":"nope","prompt":"?"},{"id":"q1","type":"text","prompt":"?"}]}',
      ),
      isNull,
    );
  });

  test('a draft of several questions posts one payload', () {
    final question = ChatPollQuestion.fromDraft(
      const ChatPollDraft(
        prompt: ' How many? ',
        type: ChatPollType.number,
        more: [
          ChatPollQuestionDraft(prompt: 'When?', type: ChatPollType.date),
          ChatPollQuestionDraft(
            prompt: 'How was it?',
            type: ChatPollType.rating,
            scale: 10,
          ),
        ],
      ),
    );
    expect(jsonDecode(question.toPayload()), {
      'quark': 'poll/1',
      'questions': [
        {'id': 'q1', 'type': 'number', 'prompt': 'How many?'},
        {'id': 'q2', 'type': 'date', 'prompt': 'When?'},
        {'id': 'q3', 'type': 'rating', 'prompt': 'How was it?', 'scale': 10},
      ],
    });
  });
}
