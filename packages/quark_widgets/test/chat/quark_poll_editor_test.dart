import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The poll form: each field reports its change through a new draft, and the
/// actions call back.
class _Harness {
  ChatPollDraft draft = const ChatPollDraft();
  var saves = 0;
  var cancels = 0;

  /// The editor, fed back every draft it reports, as a caller would.
  Widget editor({bool canSave = true}) => StatefulBuilder(
    builder: (context, setState) => QuarkPollEditor(
      draft: draft,
      onChanged: (next) => setState(() => draft = next),
      onSave: canSave ? () => saves++ : null,
      onCancel: () => cancels++,
    ),
  );
}

void main() {
  testBothViewports('shows the question, options and settings', (
    tester,
    size,
  ) async {
    await pumpAt(tester, _Harness().editor(), size: size);
    expect(find.text('New poll'), findsOneWidget);
    expect(find.byKey(const ValueKey('poll_editor_option_1')), findsOneWidget);
    expect(find.text('Anonymous'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing fills in the prompt and the options', (tester) async {
    final harness = _Harness();
    await pumpAt(tester, harness.editor());
    await tester.enterText(
      find.byKey(const ValueKey('poll_editor_prompt')),
      'Which weekend?',
    );
    await tester.enterText(
      find.byKey(const ValueKey('poll_editor_option_1')),
      'Nov 15',
    );
    expect(harness.draft.prompt, 'Which weekend?');
    expect(harness.draft.options, ['', 'Nov 15']);
    expect(harness.draft.isComplete, isFalse);
  });

  testWidgets('options are added and removed', (tester) async {
    final harness = _Harness()
      ..draft = const ChatPollDraft(options: ['a', 'b']);
    await pumpAt(tester, harness.editor());
    expect(
      find.byKey(const ValueKey('poll_editor_option_remove_0')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('poll_editor_option_add')));
    await tester.pump();
    expect(harness.draft.options, ['a', 'b', '']);
    await tester.tap(find.byKey(const ValueKey('poll_editor_option_remove_0')));
    await tester.pump();
    expect(harness.draft.options, ['b', '']);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('poll_editor_option_0')))
          .controller!
          .text,
      'b',
    );
  });

  testWidgets('number, date and rating drop the options a choice needs', (
    tester,
  ) async {
    final harness = _Harness();
    await pumpAt(tester, harness.editor());
    await tester.tap(find.byKey(const ValueKey('poll_editor_type_number')));
    await tester.pump();
    expect(harness.draft.type, ChatPollType.number);
    expect(find.byKey(const ValueKey('poll_editor_option_0')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('poll_editor_type_date')));
    await tester.pump();
    expect(find.byKey(const ValueKey('poll_editor_option_0')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('poll_editor_type_rating')));
    await tester.pump();
    expect(find.text('5'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('poll_editor_scale_more')));
    await tester.pump();
    expect(harness.draft.scale, 6);
  });

  testWidgets('a second question has to be filled in too', (tester) async {
    final harness = _Harness()
      ..draft = const ChatPollDraft(
        prompt: 'How many?',
        type: ChatPollType.number,
      );
    await pumpAt(tester, harness.editor());
    expect(harness.draft.isComplete, isTrue);
    await tester.ensureVisible(
      find.byKey(const ValueKey('poll_editor_question_add')),
    );
    await tester.tap(find.byKey(const ValueKey('poll_editor_question_add')));
    await tester.pump();
    expect(harness.draft.isComplete, isFalse);
    await tester.ensureVisible(
      find.byKey(const ValueKey('poll_editor_q1_prompt')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('poll_editor_q1_prompt')),
      'When?',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('poll_editor_q1_type_date')),
    );
    await tester.tap(find.byKey(const ValueKey('poll_editor_q1_type_date')));
    await tester.pump();
    expect(harness.draft.questions, hasLength(2));
    expect(harness.draft.questions.last.prompt, 'When?');
    expect(harness.draft.questions.last.type, ChatPollType.date);
    expect(harness.draft.isComplete, isTrue);
    await tester.ensureVisible(
      find.byKey(const ValueKey('poll_editor_question_remove_1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('poll_editor_question_remove_1')),
    );
    await tester.pump();
    expect(harness.draft.questions, hasLength(1));
  });

  testWidgets('a text poll has no options', (tester) async {
    final harness = _Harness();
    await pumpAt(tester, harness.editor());
    await tester.tap(find.byKey(const ValueKey('poll_editor_type_text')));
    await tester.pump();
    expect(harness.draft.type, ChatPollType.text);
    expect(find.byKey(const ValueKey('poll_editor_option_0')), findsNothing);
  });

  testWidgets('the settings toggle', (tester) async {
    final harness = _Harness();
    await pumpAt(tester, harness.editor());
    for (final key in [
      'poll_editor_closes',
      'poll_editor_allow_change',
      'poll_editor_anonymous',
      'poll_editor_results_after_close',
    ]) {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
    }
    final draft = harness.draft;
    expect(draft.closesAt, isNotNull);
    expect(draft.allowChange, isFalse);
    expect(draft.anonymous, isTrue);
    expect(draft.resultsAfterClose, isTrue);
    expect(
      find.byKey(const ValueKey('poll_editor_closes_date')),
      findsOneWidget,
    );
  });

  testWidgets('Post and Cancel call back, and Post waits for onSave', (
    tester,
  ) async {
    final harness = _Harness();
    await pumpAt(tester, harness.editor(canSave: false));
    final post = find.byKey(const ValueKey('poll_editor_save'));
    expect(tester.widget<FilledButton>(post).onPressed, isNull);
    await pumpAt(tester, harness.editor());
    await tester.tap(post);
    await tester.tap(find.byKey(const ValueKey('poll_editor_cancel')));
    expect(harness.saves, 1);
    expect(harness.cancels, 1);
  });
}
