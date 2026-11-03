import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The poll card: each type answers through its own inputs, and the closed,
/// answered, hidden-results and anonymous states draw what they should.
const _single = ChatPollItem(
  prompt: 'Which weekend?',
  options: ['Nov 8', 'Nov 15', 'Nov 22'],
  counts: [2, 1, 0],
  responseCount: 3,
);

final _answers = <ChatPollAnswer>[];
var _closes = 0;
var _exports = 0;

Widget _card(ChatPollItem poll, {bool author = true}) => SingleChildScrollView(
  child: QuarkPollCard(
    id: 'p1',
    poll: poll,
    onAnswer: _answers.add,
    onClose: author ? () => _closes++ : null,
    onExport: () => _exports++,
  ),
);

void main() {
  setUp(() {
    _answers.clear();
    _closes = 0;
    _exports = 0;
  });

  testBothViewports('draws the question, the options and the tally', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      _card(
        ChatPollItem(
          prompt: _single.prompt,
          options: _single.options,
          counts: _single.counts,
          responseCount: 3,
          anonymous: true,
          closesAt: DateTime(2026, 11, 7, 18),
        ),
      ),
      size: size,
    );
    expect(find.text('Which weekend?'), findsOneWidget);
    expect(find.text('Nov 15'), findsOneWidget);
    expect(find.text('2 · 67%'), findsOneWidget);
    expect(find.text('3 responses'), findsOneWidget);
    expect(find.byKey(const ValueKey('poll_anonymous_p1')), findsOneWidget);
    expect(find.text('Closes Sat, Nov 7, 2026, 6:00 PM'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single poll answers with the one option picked', (
    tester,
  ) async {
    await pumpAt(tester, _card(_single));
    final answer = find.byKey(const ValueKey('poll_answer_p1'));
    expect(tester.widget<FilledButton>(answer).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('poll_option_p1_0')));
    await tester.tap(find.byKey(const ValueKey('poll_option_p1_1')));
    await tester.pump();
    await tester.tap(answer);
    expect(_answers, [
      const ChatPollAnswer(choices: [1]),
    ]);
  });

  testWidgets('a multiple poll answers with every option ticked', (
    tester,
  ) async {
    await pumpAt(
      tester,
      _card(
        ChatPollItem(
          prompt: 'Snacks?',
          type: ChatPollType.multiple,
          options: _single.options,
        ),
      ),
    );
    for (final index in [2, 0, 1, 1]) {
      await tester.tap(find.byKey(ValueKey('poll_option_p1_$index')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('poll_answer_p1')));
    expect(_answers, [
      const ChatPollAnswer(choices: [0, 2]),
    ]);
  });

  testWidgets('a text poll answers with what was written', (tester) async {
    await pumpAt(
      tester,
      _card(
        const ChatPollItem(
          prompt: 'Ideas?',
          type: ChatPollType.text,
          textAnswers: ['A picnic'],
          responseCount: 1,
        ),
      ),
    );
    expect(find.text('A picnic'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('poll_text_p1')), 'Hike');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('poll_answer_p1')));
    expect(_answers, [const ChatPollAnswer(text: 'Hike')]);
  });

  testWidgets('an answer that cannot change disables the inputs', (
    tester,
  ) async {
    await pumpAt(
      tester,
      _card(
        const ChatPollItem(
          prompt: 'Which weekend?',
          options: ['Nov 8', 'Nov 15'],
          myAnswer: ChatPollAnswer(choices: [0]),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('poll_answer_p1')), findsNothing);
    final tile = tester.widget<RadioListTile<int>>(
      find.byKey(const ValueKey('poll_option_p1_0')),
    );
    expect(tile.enabled, isFalse);
  });

  testWidgets('an answer that can change offers "Change answer"', (
    tester,
  ) async {
    await pumpAt(
      tester,
      _card(
        const ChatPollItem(
          prompt: 'Which weekend?',
          options: ['Nov 8', 'Nov 15'],
          allowChange: true,
          myAnswer: ChatPollAnswer(choices: [0]),
        ),
      ),
    );
    expect(find.text('Change answer'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('poll_option_p1_1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('poll_answer_p1')));
    expect(_answers, [
      const ChatPollAnswer(choices: [1]),
    ]);
  });

  testWidgets('a closed poll takes no answer and cannot close again', (
    tester,
  ) async {
    await pumpAt(
      tester,
      _card(
        const ChatPollItem(
          prompt: 'Which weekend?',
          options: ['Nov 8'],
          isClosed: true,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('poll_closed_p1')), findsOneWidget);
    expect(find.byKey(const ValueKey('poll_answer_p1')), findsNothing);
    expect(find.byKey(const ValueKey('poll_close_p1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('poll_export_p1')));
    expect(_exports, 1);
  });

  testWidgets('hidden results draw the placeholder and offer no export', (
    tester,
  ) async {
    await pumpAt(
      tester,
      _card(
        const ChatPollItem(
          prompt: 'Which weekend?',
          options: ['Nov 8'],
          resultsAfterClose: true,
          resultsVisible: false,
        ),
        author: false,
      ),
    );
    expect(
      find.byKey(const ValueKey('poll_results_hidden_p1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('poll_tally_p1_0')), findsNothing);
    expect(find.byKey(const ValueKey('poll_export_p1')), findsNothing);
    expect(find.byKey(const ValueKey('poll_close_p1')), findsNothing);
  });

  testWidgets('"Close poll" calls back', (tester) async {
    await pumpAt(tester, _card(_single));
    await tester.tap(find.byKey(const ValueKey('poll_close_p1')));
    expect(_closes, 1);
  });

  testWidgets('a poll message draws its card, closable only by its author', (
    tester,
  ) async {
    final closed = <String>[];
    ChatMessageItem poll(String id, String author) => ChatMessageItem(
      id: id,
      authorId: author,
      authorName: author,
      sentAt: DateTime(2026, 11, 2, 9),
      kind: ChatMessageKind.poll,
      poll: _single,
    );
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: [poll('m1', 'ada'), poll('m2', 'bob')],
        currentUserId: 'ada',
        onClosePoll: closed.add,
        onAnswerPoll: (_, _) {},
      ),
    );
    expect(find.byKey(const ValueKey('poll_close_m2')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('poll_close_m1')));
    expect(closed, ['m1']);
  });
}
