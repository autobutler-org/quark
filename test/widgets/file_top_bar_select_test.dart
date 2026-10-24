import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/file_top_bar.dart';
import '../support/tap_target_guidelines.dart' show setViewport;

/// #2057: Files has had multi-select and batch delete since #986, entered by
/// long-pressing a row. A mouse does not long-press, so on the web the whole
/// feature was invisible and Files looked like it had no bulk actions at all.
/// The toolbar now offers the same entry point a pointer can reach.
void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    VoidCallback? onStartSelection,
  }) async {
    setViewport(tester, const Size(1400, 900));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: testFileTopBar(onStartSelection: onStartSelection),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the toolbar can start a selection', (tester) async {
    var starts = 0;
    await pumpBar(tester, onStartSelection: () => starts++);

    final select = find.byKey(const ValueKey('file_top_bar_select'));
    expect(select, findsOneWidget);
    expect(find.byTooltip('Select'), findsOneWidget);

    await tester.tap(select);
    await tester.pump();

    expect(starts, 1);
  });

  testWidgets('nothing is offered where selecting makes no sense', (
    tester,
  ) async {
    await pumpBar(tester);

    expect(find.byKey(const ValueKey('file_top_bar_select')), findsNothing);
  });
}
