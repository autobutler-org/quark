import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/keyboard.dart';
import '../support/pump.dart';

void main() {
  Future<List<String>> pumpDialog(
    WidgetTester tester, {
    Size size = wideViewport,
    List<String>? events,
  }) async {
    final created = <String>[];
    await pumpAt(
      tester,
      NewFileDialog(
        onCreate: created.add,
        onCancel: () => events?.add('cancel'),
      ),
      size: size,
    );
    return created;
  }

  testWidgets('offers every type and defaults to the first', (tester) async {
    await pumpDialog(tester);

    for (final type in kNewFileTypes) {
      expect(find.text(type.label), findsOneWidget);
      final slug = type.extension.isEmpty
          ? 'generic'
          : type.extension.substring(1);
      expect(find.byKey(ValueKey('new_file_type_$slug')), findsOneWidget);
    }
    expect(find.text('.qdoc'), findsOneWidget);
  });

  for (final (type, name, expected) in [
    (null, 'notes', 'notes.qdoc'),
    ('qsheet', 'budget', 'budget.qsheet'),
    ('generic', 'readme.txt', 'readme.txt'),
  ]) {
    testWidgets('creates $expected from $name as ${type ?? 'the default'}', (
      tester,
    ) async {
      final created = await pumpDialog(tester);

      if (type != null) {
        await tester.tap(find.byKey(ValueKey('new_file_type_$type')));
        await tester.pump();
      }
      await tester.enterText(find.byKey(const ValueKey('new_file_name')), name);
      await tester.tap(find.byKey(const ValueKey('new_file_create')));
      await tester.pump();

      expect(created, [expected]);
    });
  }

  testWidgets('hints a name that matches the selected type', (tester) async {
    await pumpDialog(tester);

    expect(find.text('Untitled document'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('new_file_type_qsheet')));
    await tester.pump();

    expect(find.text('Untitled spreadsheet'), findsOneWidget);
    expect(find.text('Untitled document'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('new_file_type_qdoc')));
    await tester.pump();

    expect(find.text('Untitled document'), findsOneWidget);
    expect(find.text('Untitled spreadsheet'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('new_file_type_generic')));
    await tester.pump();

    expect(find.text('filename.txt'), findsOneWidget);
    expect(find.text('Untitled document'), findsNothing);
  });

  for (final (name, refusal) in [
    ('', 'Name cannot be empty'),
    ('a/b', 'Name cannot contain slashes'),
  ]) {
    testWidgets('refuses "$name": $refusal', (tester) async {
      final created = await pumpDialog(tester);

      if (name.isNotEmpty) {
        await tester.enterText(
          find.byKey(const ValueKey('new_file_name')),
          name,
        );
      }
      await tester.tap(find.byKey(const ValueKey('new_file_create')));
      await tester.pump();

      expect(created, isEmpty);
      expect(find.text(refusal), findsOneWidget);
    });
  }

  testWidgets('cancels through its callback rather than popping itself', (
    tester,
  ) async {
    final events = <String>[];
    await pumpDialog(tester, size: narrowViewport, events: events);

    await tester.tap(find.byKey(const ValueKey('new_file_cancel')));
    await tester.pump();

    expect(events, ['cancel']);
  });

  testWidgets('announces each type as a choice, the picked one selected', (
    tester,
  ) async {
    await pumpDialog(tester);
    final handle = tester.ensureSemantics();
    await tester.tap(find.byKey(const ValueKey('new_file_type_qsheet')));
    await tester.pump();

    for (final (slug, selected) in const [('qsheet', true), ('qdoc', false)]) {
      final flags = tester
          .getSemantics(find.byKey(ValueKey('new_file_type_$slug')))
          .flagsCollection;
      expect(flags.isButton, isTrue, reason: slug);
      expect(flags.isInMutuallyExclusiveGroup, isTrue, reason: slug);
      expect(flags.isSelected, selected ? Tristate.isTrue : Tristate.isFalse);
    }
    handle.dispose();
    await expectTapTargetGuidelines(tester);
  });

  // #2604: the type cards were bare gesture detectors a keyboard could not
  // reach.
  testWidgets('a type is picked from the keyboard', (tester) async {
    final created = await pumpDialog(tester);
    final handle = tester.ensureSemantics();

    final card = find.byKey(const ValueKey('new_file_type_qdoc'));
    await tabTo(tester, card);
    expect(findFocusRing(card), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(
      tester.getSemantics(card).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(created, isEmpty);
    handle.dispose();
  });
}
