import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/chat/chat_unlock_prompt.dart';

import '../../support/tap_target_guidelines.dart';

/// #2489: the unlock prompt hands the password over once and keeps no copy of
/// it in the field afterward, on narrow and wide viewports alike.
void main() {
  final field = find.byKey(const ValueKey('chat_unlock_password'));
  final submit = find.byKey(const ValueKey('chat_unlock_submit'));

  Future<List<String>> pumpPrompt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final unlocks = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatUnlockPrompt(onUnlock: unlocks.add)),
      ),
    );
    return unlocks;
  }

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(field).controller!.text;

  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    testWidgets('the button submits and clears the password at $size', (
      tester,
    ) async {
      final unlocks = await pumpPrompt(tester, size);
      await tester.enterText(field, 'hunter2');
      await tester.tap(submit);
      await tester.pump();
      expect(unlocks, ['hunter2']);
      expect(fieldText(tester), isEmpty);
    });

    testWidgets('enter submits and clears the password at $size', (
      tester,
    ) async {
      final unlocks = await pumpPrompt(tester, size);
      await tester.enterText(field, 'hunter2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(unlocks, ['hunter2']);
      expect(fieldText(tester), isEmpty);
    });
  }

  testWidgets('an empty password is not submitted', (tester) async {
    final unlocks = await pumpPrompt(tester, const Size(1280, 800));
    await tester.tap(submit);
    await tester.pump();
    expect(unlocks, isEmpty);
  });

  testWidgets('the field sits in an autofill group', (tester) async {
    await pumpPrompt(tester, const Size(1280, 800));
    expect(
      find.ancestor(of: field, matching: find.byType(AutofillGroup)),
      findsOneWidget,
    );
  });

  // #2494: the prompt says why it asks, which password, where keys live, and
  // that a wrong try is harmless, before and after a failure.
  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    testWidgets('explains the unlock at $size', (tester) async {
      await pumpPrompt(tester, size);
      for (final (_, line) in ChatUnlockPrompt.explanation) {
        expect(find.text(line), findsOneWidget);
      }
      expect(find.text(ChatUnlockPrompt.failureHint), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a failure says what to try next', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatUnlockPrompt(onUnlock: (_) {}, error: 'Nope.'),
        ),
      ),
    );
    expect(find.text('Nope.'), findsOneWidget);
    expect(find.text(ChatUnlockPrompt.failureHint), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // #2603, #2605: the prompt's field and button are labeled 48dp targets.
  for (final size in const [narrowViewport, wideViewport]) {
    testWidgets('every control is a labeled 48dp target at $size', (
      tester,
    ) async {
      await pumpPrompt(tester, size);
      await expectTapTargetGuidelines(tester);
    });
  }
}
