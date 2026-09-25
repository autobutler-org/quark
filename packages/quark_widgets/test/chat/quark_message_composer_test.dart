import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The field messages are written in (#2420): the send button sends
/// everywhere, Enter sends only on a desktop, a blank message never sends,
/// and a user who may not write sees why instead of a field.
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

  testBothViewports('never sends a blank message', (tester, size) async {
    final sent = <String>[];
    await pumpAt(tester, QuarkMessageComposer(onSend: sent.add), size: size);

    expect(tester.widget<IconButton>(find.byKey(send)).onPressed, isNull);
    await tester.enterText(find.byKey(field), '   ');
    await tester.pump();
    expect(tester.widget<IconButton>(find.byKey(send)).onPressed, isNull);
    expect(sent, isEmpty);
  });

  testBothViewports('Enter sends on a desktop', (tester, size) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final sent = <String>[];
    await pumpAt(tester, QuarkMessageComposer(onSend: sent.add), size: size);

    await tester.enterText(find.byKey(field), 'hi');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sent, ['hi']);
    debugDefaultTargetPlatformOverride = null;
  });

  testBothViewports('Shift+Enter does not send on a desktop', (
    tester,
    size,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final sent = <String>[];
    await pumpAt(tester, QuarkMessageComposer(onSend: sent.add), size: size);

    await tester.enterText(find.byKey(field), 'hi');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(sent, isEmpty);
    debugDefaultTargetPlatformOverride = null;
  });

  testBothViewports('Enter confirms an input method, it does not send', (
    tester,
    size,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final sent = <String>[];
    await pumpAt(tester, QuarkMessageComposer(onSend: sent.add), size: size);

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

  testBothViewports('Enter does not send on a phone', (tester, size) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final sent = <String>[];
    await pumpAt(tester, QuarkMessageComposer(onSend: sent.add), size: size);

    await tester.enterText(find.byKey(field), 'hi');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sent, isEmpty);
    debugDefaultTargetPlatformOverride = null;
  });

  testBothViewports('shows why instead of a field when writing is off', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkMessageComposer(
        onSend: (_) {},
        disabledReason: 'You can read this channel but not write in it',
      ),
      size: size,
    );

    expect(
      find.byKey(const ValueKey('message_composer_disabled')),
      findsOneWidget,
    );
    expect(
      find.text('You can read this channel but not write in it'),
      findsOneWidget,
    );
    expect(find.byKey(field), findsNothing);
    expect(find.byKey(send), findsNothing);
  });

  testWidgets('shows the hint it is given', (tester) async {
    await pumpAt(
      tester,
      QuarkMessageComposer(onSend: (_) {}, hintText: 'Message #general'),
    );
    expect(find.text('Message #general'), findsOneWidget);
  });

  testWidgets('the send button carries a tooltip', (tester) async {
    await pumpAt(tester, QuarkMessageComposer(onSend: (_) {}));
    expect(tester.widget<IconButton>(find.byKey(send)).tooltip, 'Send');
  });

  testBothViewports('survives a long unbroken word', (tester, size) async {
    await pumpAt(tester, QuarkMessageComposer(onSend: (_) {}), size: size);
    await tester.enterText(find.byKey(field), 'x' * 2000);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
