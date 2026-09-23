import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

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

  testBothViewports('offers every type and defaults to the first', (
    tester,
    size,
  ) async {
    await pumpDialog(tester, size: size);

    for (final type in kNewFileTypes) {
      expect(find.text(type.label), findsOneWidget);
      final slug = type.extension.isEmpty
          ? 'generic'
          : type.extension.substring(1);
      expect(find.byKey(ValueKey('new_file_type_$slug')), findsOneWidget);
    }
    expect(find.text('.qdoc'), findsOneWidget);
  });

  testBothViewports('appends the selected extension to the name', (
    tester,
    size,
  ) async {
    final created = await pumpDialog(tester, size: size);

    await tester.enterText(
      find.byKey(const ValueKey('new_file_name')),
      'notes',
    );
    await tester.tap(find.byKey(const ValueKey('new_file_create')));
    await tester.pump();

    expect(created, ['notes.qdoc']);
  });

  testBothViewports('hints a name that matches the selected type', (
    tester,
    size,
  ) async {
    await pumpDialog(tester, size: size);

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

  testBothViewports('switches the extension with the type', (
    tester,
    size,
  ) async {
    final created = await pumpDialog(tester, size: size);

    await tester.tap(find.byKey(const ValueKey('new_file_type_qsheet')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('new_file_name')),
      'budget',
    );
    await tester.tap(find.byKey(const ValueKey('new_file_create')));
    await tester.pump();

    expect(created, ['budget.qsheet']);
  });

  testWidgets('leaves a generic filename exactly as typed', (tester) async {
    final created = await pumpDialog(tester, size: narrowViewport);

    await tester.tap(find.byKey(const ValueKey('new_file_type_generic')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('new_file_name')),
      'readme.txt',
    );
    await tester.tap(find.byKey(const ValueKey('new_file_create')));
    await tester.pump();

    expect(created, ['readme.txt']);
  });

  testWidgets('refuses an empty name', (tester) async {
    final created = await pumpDialog(tester, size: wideViewport);

    await tester.tap(find.byKey(const ValueKey('new_file_create')));
    await tester.pump();

    expect(created, isEmpty);
    expect(find.text('Name cannot be empty'), findsOneWidget);
  });

  testWidgets('refuses a name with a slash in it', (tester) async {
    final created = await pumpDialog(tester, size: wideViewport);

    await tester.enterText(find.byKey(const ValueKey('new_file_name')), 'a/b');
    await tester.tap(find.byKey(const ValueKey('new_file_create')));
    await tester.pump();

    expect(created, isEmpty);
    expect(find.text('Name cannot contain slashes'), findsOneWidget);
  });

  testWidgets('cancels through its callback rather than popping itself', (
    tester,
  ) async {
    final events = <String>[];
    await pumpDialog(tester, size: narrowViewport, events: events);

    await tester.tap(find.byKey(const ValueKey('new_file_cancel')));
    await tester.pump();

    expect(events, ['cancel']);
  });
}
