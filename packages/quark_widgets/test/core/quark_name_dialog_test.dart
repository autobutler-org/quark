import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// Naming a group, and anything else with a name (#1910). The part worth
/// guarding is that an empty name never leaves, the name leaves trimmed, and
/// a refusal shows in the open dialog.
void main() {
  Future<List<String>> pumpDialog(
    WidgetTester tester, {
    Size size = wideViewport,
    List<String>? events,
    String initialName = '',
    int? maxLength,
    bool isSubmitting = false,
    String? error,
    String title = 'New group',
    Brightness brightness = Brightness.dark,
  }) async {
    final submitted = <String>[];
    await pumpAt(
      tester,
      QuarkNameDialog(
        title: title,
        label: 'Group name',
        submitLabel: 'Create',
        initialName: initialName,
        maxLength: maxLength,
        isSubmitting: isSubmitting,
        error: error,
        onSubmit: submitted.add,
        onCancel: () => events?.add('cancel'),
      ),
      size: size,
      brightness: brightness,
    );
    return submitted;
  }

  Finder field() => find.byKey(const ValueKey('name_dialog_field'));

  FilledButton submitButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.byKey(const ValueKey('name_dialog_submit')),
  );

  testBothViewports('hands back the name trimmed', (tester, size) async {
    final submitted = await pumpDialog(tester, size: size);

    await tester.enterText(field(), '  Family  ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('name_dialog_submit')));
    await tester.pump();

    expect(submitted, ['Family']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('submits from the keyboard', (tester) async {
    final submitted = await pumpDialog(tester);

    await tester.enterText(field(), 'Family');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(submitted, ['Family']);
  });

  testWidgets('never submits an empty or blank name', (tester) async {
    final submitted = await pumpDialog(tester);

    expect(submitButton(tester).onPressed, isNull);

    await tester.enterText(field(), '   ');
    await tester.pump();
    expect(submitButton(tester).onPressed, isNull);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submitted, isEmpty);
  });

  testWidgets('starts from the name being renamed', (tester) async {
    final submitted = await pumpDialog(tester, initialName: 'Family');

    expect(find.text('Family'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('name_dialog_submit')));
    await tester.pump();

    expect(submitted, ['Family']);
  });

  testWidgets('stops at the longest name allowed', (tester) async {
    final submitted = await pumpDialog(tester, maxLength: 64);

    await tester.enterText(field(), 'x' * 70);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('name_dialog_submit')));
    await tester.pump();

    expect(submitted.single, hasLength(64));
    expect(find.text('64/64'), findsOneWidget);
  });

  testBothViewports('cancels through its key', (tester, size) async {
    final events = <String>[];
    await pumpDialog(tester, size: size, events: events);

    await tester.tap(find.byKey(const ValueKey('name_dialog_cancel')));
    await tester.pump();

    expect(events, ['cancel']);
  });

  testWidgets('holds both buttons while submitting', (tester) async {
    final events = <String>[];
    final submitted = await pumpDialog(
      tester,
      initialName: 'Family',
      isSubmitting: true,
      events: events,
    );

    expect(submitButton(tester).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('name_dialog_cancel')));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(submitted, isEmpty);
    expect(events, isEmpty);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('name_dialog_submit')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
  });

  testBothViewports('shows the refusal the caller handed it', (
    tester,
    size,
  ) async {
    await pumpDialog(
      tester,
      size: size,
      error: 'A group with that name already exists.',
    );

    expect(find.text('A group with that name already exists.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('survives a long title and a long refusal', (
    tester,
    size,
  ) async {
    await pumpDialog(
      tester,
      size: size,
      title: 'Rename ${'a very long group name ' * 6}',
      error: 'That did not work. ' * 12,
    );

    expect(tester.takeException(), isNull);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: the refusal reads in the error color', (tester) async {
      await pumpDialog(tester, error: 'Nope.', brightness: brightness);

      expect(tester.takeException(), isNull);
      expect(
        tester.widget<Text>(find.text('Nope.')).style?.color,
        tokens.error,
      );
    });
  }
}
