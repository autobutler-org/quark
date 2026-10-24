import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The field messages are written in (#2420, #3256): the send button sends
/// everywhere, a hardware Enter sends and Shift+Enter inserts a newline on
/// every platform, a blank message never sends, and a user who may not write
/// sees why instead of a field.
void main() {
  const field = ValueKey('message_composer_field');
  const send = ValueKey('message_composer_send');

  testBothViewports('sends the trimmed text from the button and clears', (
    tester,
    size,
  ) async {
    final sent = <String>[];
    await pumpAt(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: QuarkMessageComposer(onSend: sent.add),
      ),
      size: size,
    );

    await tester.enterText(find.byKey(field), '  hello there  ');
    await tester.pump();
    await tester.tap(find.byKey(send));
    await tester.pump();

    expect(sent, ['hello there']);
    expect(find.text('hello there'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // #3254: a channel switch builds a new composer. It has to show the draft
  // it was given, and report edits so the caller can keep them.
  testBothViewports('shows a restored draft and reports edits', (
    tester,
    size,
  ) async {
    final edits = <String>[];
    await pumpAt(
      tester,
      QuarkMessageComposer(
        initialText: 'draft',
        onChanged: edits.add,
        onSend: (_) {},
      ),
      size: size,
    );

    expect(
      tester.widget<TextField>(find.byKey(field)).controller!.text,
      'draft',
    );
    expect(edits, isEmpty);

    await tester.enterText(find.byKey(field), 'draft plus');
    await tester.pump();
    expect(edits, ['draft plus']);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('sending a restored draft clears it and reports empty', (
    tester,
    size,
  ) async {
    final edits = <String>[];
    final sent = <String>[];
    await pumpAt(
      tester,
      QuarkMessageComposer(
        initialText: 'hello',
        onChanged: edits.add,
        onSend: sent.add,
      ),
      size: size,
    );

    await tester.tap(find.byKey(send));
    await tester.pump();
    expect(sent, ['hello']);
    expect(edits, ['']);
    expect(
      tester.widget<TextField>(find.byKey(field)).controller!.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('never sends a blank message', (tester) async {
    final sent = <String>[];
    await pumpAt(tester, QuarkMessageComposer(onSend: sent.add));

    expect(tester.widget<IconButton>(find.byKey(send)).onPressed, isNull);
    await tester.enterText(find.byKey(field), '   ');
    await tester.pump();
    expect(tester.widget<IconButton>(find.byKey(send)).onPressed, isNull);
    expect(sent, isEmpty);
  });

  // #3256: hardware Enter sends on a phone as well as a desktop.
  // Shift+Enter inserts a newline. The on-screen keyboard shows Send.
  for (final platform in const [TargetPlatform.macOS, TargetPlatform.android]) {
    final where = platform == TargetPlatform.macOS ? 'desktop' : 'phone';

    testWidgets('a hardware Enter sends on a $where', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final sent = <String>[];
      await pumpAt(tester, QuarkMessageComposer(onSend: sent.add));

      await tester.enterText(find.byKey(field), 'hi');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sent, ['hi']);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Shift+Enter inserts a newline on a $where', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final sent = <String>[];
      await pumpAt(tester, QuarkMessageComposer(onSend: sent.add));

      await tester.enterText(find.byKey(field), 'hi');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(sent, isEmpty);
      final controller = tester
          .widget<TextField>(find.byKey(field))
          .controller!;
      expect(controller.text, 'hi\n');
      expect(controller.selection, const TextSelection.collapsed(offset: 3));
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('the on-screen keyboard shows Send and sends', (tester) async {
    final sent = <String>[];
    await pumpAt(tester, QuarkMessageComposer(onSend: sent.add));

    expect(
      tester.widget<TextField>(find.byKey(field)).textInputAction,
      TextInputAction.send,
    );
    await tester.showKeyboard(find.byKey(field));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'hi',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(sent, ['hi']);
  });

  testWidgets('Enter confirms an input method, it does not send', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final sent = <String>[];
    await pumpAt(tester, QuarkMessageComposer(onSend: sent.add));

    await tester.showKeyboard(find.byKey(field));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'nihon',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sent, isEmpty);

    // Once the composition is confirmed, Enter sends.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'nihon',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sent, ['nihon']);
    debugDefaultTargetPlatformOverride = null;
  });

  // Each composer shows its reason in place of the field, or the field
  // itself when nothing stops the account from writing.
  for (final (label, composer, reason, notShown) in [
    (
      'shows why instead of a field when writing is off',
      QuarkMessageComposer(
        onSend: (_) {},
        disabledReason: 'You can read this channel but not write in it',
      ),
      'You can read this channel but not write in it',
      const <String>[],
    ),
    (
      'a viewer sees why they cannot send, not a field',
      QuarkMessageComposer(
        onSend: (_) {},
        permissions: ChatPermissionPreset.viewer.permissions,
        isWaitingForKey: true,
      ),
      QuarkMessageComposer.noSendReason,
      [QuarkMessageComposer.waitingForKeyReason],
    ),
    (
      'a member waiting for the key sees a different reason',
      QuarkMessageComposer(
        onSend: (_) {},
        permissions: ChatPermissionPreset.member.permissions,
        isWaitingForKey: true,
      ),
      QuarkMessageComposer.waitingForKeyReason,
      [QuarkMessageComposer.noSendReason],
    ),
    (
      'a delegated manager is told they are not a member',
      QuarkMessageComposer(
        onSend: (_) {},
        permissions: const {ChatPermission.manageMembers},
        isWaitingForKey: true,
      ),
      QuarkMessageComposer.notMemberReason,
      [QuarkMessageComposer.waitingForKeyReason],
    ),
    (
      'a member with the full set gets the field',
      QuarkMessageComposer(
        onSend: (_) {},
        permissions: ChatPermissionPreset.owner.permissions,
      ),
      null,
      const <String>[],
    ),
  ]) {
    testWidgets(label, (tester) async {
      await pumpAt(tester, composer);

      final disabled = find.byKey(const ValueKey('message_composer_disabled'));
      if (reason == null) {
        expect(find.byKey(field), findsOneWidget);
        expect(disabled, findsNothing);
        return;
      }
      expect(disabled, findsOneWidget);
      expect(find.text(reason), findsOneWidget);
      for (final text in notShown) {
        expect(find.text(text), findsNothing);
      }
      expect(find.byKey(field), findsNothing);
      expect(find.byKey(send), findsNothing);
    });
  }

  testBothViewports('survives a long unbroken word', (tester, size) async {
    await pumpAt(tester, QuarkMessageComposer(onSend: (_) {}), size: size);
    await tester.enterText(find.byKey(field), 'x' * 2000);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  // #2502: Enter on a blank message did nothing, with nothing to say why.
  testWidgets('Enter on a blank message says what is missing', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final sent = <String>[];
    await pumpAt(tester, QuarkMessageComposer(onSend: sent.add));

    expect(
      tester.widget<IconButton>(find.byKey(send)).tooltip,
      QuarkMessageComposer.blankHint,
    );
    await tester.enterText(find.byKey(field), '   ');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sent, isEmpty);
    expect(find.byKey(const ValueKey('message_composer_hint')), findsOne);
    expect(find.text(QuarkMessageComposer.blankHint), findsOne);

    await tester.enterText(find.byKey(field), 'hi');
    await tester.pump();
    expect(find.byKey(const ValueKey('message_composer_hint')), findsNothing);
    expect(tester.widget<IconButton>(find.byKey(send)).tooltip, 'Send');
    debugDefaultTargetPlatformOverride = null;
  });

  // #2503: a message of any length went out with no word about a limit.
  testBothViewports('counts down near maxLength and refuses past it', (
    tester,
    size,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const counter = ValueKey('message_composer_counter');
    final sent = <String>[];
    await pumpAt(
      tester,
      QuarkMessageComposer(onSend: sent.add, maxLength: 100),
      size: size,
    );

    await tester.enterText(find.byKey(field), 'x' * 50);
    await tester.pump();
    expect(find.byKey(counter), findsNothing);

    await tester.enterText(find.byKey(field), 'x' * 95);
    await tester.pump();
    expect(find.byKey(counter), findsOne);
    expect(find.text('5 characters left'), findsOne);

    await tester.enterText(find.byKey(field), 'x' * 103);
    await tester.pump();
    expect(find.text(QuarkMessageComposer.overLimitText(3)), findsOne);
    expect(find.byKey(counter), findsNothing);
    expect(tester.widget<IconButton>(find.byKey(send)).onPressed, isNull);
    expect(
      tester.widget<IconButton>(find.byKey(send)).tooltip,
      QuarkMessageComposer.tooLongText,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sent, isEmpty);
    expect(find.byKey(field), findsOne, reason: 'the draft is kept');

    await tester.enterText(find.byKey(field), 'x' * 100);
    await tester.pump();
    await tester.tap(find.byKey(send));
    await tester.pump();
    expect(sent, ['x' * 100]);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  // #2623: typing @ suggests the members, and picking one writes the mention.
  group('mentions', () {
    const names = ['ada', 'ann', 'bob'];
    const suggestions = ValueKey('mention_suggestions');

    testBothViewports('typing @ suggests the names that match', (
      tester,
      size,
    ) async {
      await pumpAt(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: QuarkMessageComposer(onSend: (_) {}, mentionNames: names),
        ),
        size: size,
      );
      expect(find.byKey(suggestions), findsNothing);

      await tester.enterText(find.byKey(field), 'hi @a');
      await tester.pump();
      expect(find.byKey(const ValueKey('mention_suggestion_ada')), findsOne);
      expect(find.byKey(const ValueKey('mention_suggestion_ann')), findsOne);
      expect(
        find.byKey(const ValueKey('mention_suggestion_bob')),
        findsNothing,
      );

      await tester.enterText(find.byKey(field), 'hi @zed');
      await tester.pump();
      expect(find.byKey(suggestions), findsNothing);

      await tester.enterText(find.byKey(field), 'mail a@a');
      await tester.pump();
      expect(find.byKey(suggestions), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tap writes the mention and sends it as text', (
      tester,
    ) async {
      final sent = <String>[];
      await pumpAt(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: QuarkMessageComposer(onSend: sent.add, mentionNames: names),
        ),
      );

      await tester.enterText(find.byKey(field), 'hi @b');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mention_suggestion_bob')));
      await tester.pump();

      final text = tester.widget<TextField>(find.byKey(field)).controller!;
      expect(text.text, 'hi @bob ');
      expect(text.selection, const TextSelection.collapsed(offset: 8));
      expect(find.byKey(suggestions), findsNothing);

      await tester.tap(find.byKey(send));
      await tester.pump();
      expect(sent, ['hi @bob']);
    });

    testWidgets('the keyboard moves, picks and closes', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final sent = <String>[];
      await pumpAt(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: QuarkMessageComposer(onSend: sent.add, mentionNames: names),
        ),
      );
      String highlighted() => tester
          .widget<QuarkMentionSuggestions>(find.byType(QuarkMentionSuggestions))
          .highlighted!;
      final text = tester.widget<TextField>(find.byKey(field)).controller!;

      await tester.enterText(find.byKey(field), '@a');
      await tester.pump();
      expect(highlighted(), 'ada');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(highlighted(), 'ann');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(highlighted(), 'ada', reason: 'wraps');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(highlighted(), 'ann');

      // Enter picks rather than sends while the list is open.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(text.text, '@ann ');
      expect(sent, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(sent, ['@ann']);

      await tester.enterText(find.byKey(field), '@b');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(text.text, '@bob ');

      // Escape closes the list for that @, and Enter sends again.
      await tester.enterText(find.byKey(field), '@a');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(suggestions), findsNothing);
      await tester.enterText(find.byKey(field), '@an');
      await tester.pump();
      expect(find.byKey(suggestions), findsNothing);
      await tester.enterText(find.byKey(field), 'x @a');
      await tester.pump();
      expect(find.byKey(suggestions), findsOne, reason: 'another @');
      debugDefaultTargetPlatformOverride = null;
    });

    testBothViewports('a mention that names a member is drawn apart', (
      tester,
      size,
    ) async {
      await pumpAt(
        tester,
        QuarkMessageComposer(onSend: (_) {}, mentionNames: names),
        size: size,
      );
      List<String> styled() {
        final context = tester.element(find.byKey(field));
        final span = tester
            .widget<TextField>(find.byKey(field))
            .controller!
            .buildTextSpan(context: context, withComposing: false);
        return [
          for (final child in span.children ?? const <InlineSpan>[])
            if (child is TextSpan && child.style?.backgroundColor != null)
              child.text!,
        ];
      }

      await tester.enterText(find.byKey(field), 'hi @bob and @carol');
      await tester.pump();
      expect(styled(), ['@bob']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no names suggests nothing', (tester) async {
      await pumpAt(tester, QuarkMessageComposer(onSend: (_) {}));

      await tester.enterText(find.byKey(field), '@a');
      await tester.pump();
      expect(find.byKey(suggestions), findsNothing);
    });
  });
}
