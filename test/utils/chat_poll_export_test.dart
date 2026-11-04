import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/chat_message.dart';
import 'package:quark/models/chat_poll.dart';
import 'package:quark/utils/chat_poll_export.dart';
import 'package:quark_widgets/quark_widgets.dart';

ChatOpenPollAnswer answer(int id, int? userId, ChatPollAnswer? answer) =>
    ChatOpenPollAnswer(
      response: ChatPollResponse(
        id: id,
        messageId: 5,
        userId: userId,
        keyVersion: 1,
        ciphertext: Uint8List(0),
      ),
      answer: answer,
    );

ChatTimelineMessage poll(
  ChatPollQuestion question,
  List<ChatOpenPollAnswer> answers, {
  bool anonymous = false,
}) => ChatTimelineMessage(
  message: ChatMessage(
    id: 5,
    channelId: 1,
    authorId: 7,
    keyVersion: 1,
    ciphertext: null,
    createdAt: DateTime.utc(2026, 11, 2),
    poll: ChatPoll(anonymous: anonymous),
  ),
  state: ChatMessageState.ready,
  question: question,
  pollAnswers: answers,
);

const colors = ChatPollQuestion(
  prompt: 'Favorite colors, in order?',
  type: ChatPollType.multiple,
  options: ['Red', 'Green, light', 'Blue'],
);

String nameOf(int id) => {7: 'ada', 8: 'Grace "Amazing" Hopper'}[id]!;

void main() {
  final named = poll(colors, [
    answer(1, 7, const ChatPollAnswer(choices: [0, 2])),
    answer(2, 9, null), // Didn't open: left out.
    answer(3, 8, const ChatPollAnswer(choices: [1])),
  ]);

  test('one row per respondent, choices as their labels', () {
    expect(chatPollExportRows(named, nameOf), [
      ['Name', 'Favorite colors, in order?'],
      ['ada', 'Red; Blue'],
      ['Grace "Amazing" Hopper', 'Green, light'],
    ]);
  });

  test('an anonymous poll names nobody, not even a Name column', () {
    final anonymous = poll(colors, [
      answer(1, null, const ChatPollAnswer(choices: [1])),
    ], anonymous: true);
    final rows = chatPollExportRows(
      anonymous,
      (_) => fail('an anonymous poll asks for no names'),
    );
    expect(rows, [
      ['Favorite colors, in order?'],
      ['Green, light'],
    ]);
    expect(jsonDecode(chatPollExport(rows, ChatPollExportFormat.json)), [
      {'Favorite colors, in order?': 'Green, light'},
    ]);
  });

  test('a text answer is exported as written', () {
    final text = poll(
      const ChatPollQuestion(prompt: 'Why?', type: ChatPollType.text),
      [answer(1, 7, const ChatPollAnswer(text: 'Because\nreasons'))],
    );
    expect(chatPollExportRows(text, nameOf).last, ['ada', 'Because\nreasons']);
  });

  test('csv quotes commas, quotes and line breaks', () {
    expect(
      chatPollExport(
        chatPollExportRows(named, nameOf),
        ChatPollExportFormat.csv,
      ),
      'Name,"Favorite colors, in order?"\n'
      'ada,Red; Blue\n'
      '"Grace ""Amazing"" Hopper","Green, light"',
    );
  });

  test('json is one object per respondent keyed by the header', () {
    expect(
      jsonDecode(
        chatPollExport(
          chatPollExportRows(named, nameOf),
          ChatPollExportFormat.json,
        ),
      ),
      [
        {'Name': 'ada', 'Favorite colors, in order?': 'Red; Blue'},
        {
          'Name': 'Grace "Amazing" Hopper',
          'Favorite colors, in order?': 'Green, light',
        },
      ],
    );
  });

  test('qsheet puts the rows on one Results tab', () {
    final rows = chatPollExportRows(named, nameOf);
    expect(jsonDecode(chatPollExport(rows, ChatPollExportFormat.qsheet)), {
      'tabs': [
        {
          'name': 'Results',
          'data': {'rows': rows},
        },
      ],
    });
  });

  test('one column per question, with a number on a repeated prompt', () {
    final trip = ChatPollQuestion(
      prompt: 'How many?',
      type: ChatPollType.number,
      more: const [
        ChatPollQuestion(id: 'q2', prompt: 'When?', type: ChatPollType.date),
        ChatPollQuestion(id: 'q3', prompt: 'When?', type: ChatPollType.date),
        ChatPollQuestion(
          id: 'q4',
          prompt: 'How was it?',
          type: ChatPollType.rating,
          scale: 5,
        ),
      ],
    );
    expect(
      chatPollExportRows(
        poll(trip, [
          answer(
            1,
            7,
            const ChatPollAnswer(
              parts: [
                ChatPollAnswer(number: '4'),
                ChatPollAnswer(date: '2026-11-08'),
                ChatPollAnswer(date: '2026-11-15'),
                ChatPollAnswer(rating: 5),
              ],
            ),
          ),
        ]),
        nameOf,
      ),
      [
        ['Name', 'How many?', 'When?', 'When? (2)', 'How was it?'],
        ['ada', '4', '2026-11-08', '2026-11-15', '5'],
      ],
    );
  });

  test('the file is named after the prompt, made safe for a file system', () {
    expect(
      ChatPollExportFormat.csv.fileNameFor('Where for lunch?'),
      'Where for lunch.csv',
    );
    expect(
      ChatPollExportFormat.json.fileNameFor(' a/b:c\n  d. '),
      'abc d.json',
    );
    expect(
      ChatPollExportFormat.qsheet.fileNameFor('?/..'),
      'poll_results.qsheet',
    );
    expect(ChatPollExportFormat.csv.fileNameFor('x' * 200), '${'x' * 80}.csv');
  });
}
