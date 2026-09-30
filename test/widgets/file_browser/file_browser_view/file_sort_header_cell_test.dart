import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_sort_header_cell.dart';
import 'package:flutter/services.dart';
import 'package:quark_widgets/quark_widgets.dart';
import '../../../support/tab_to.dart';

/// #2603: the sort state was only an arrow glyph, which a screen reader
/// never heard.
void main() {
  Future<void> pumpCell(
    WidgetTester tester, {
    required SortColumn sortColumn,
    SortDirection sortDirection = SortDirection.asc,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            FileSortHeaderCell(
              key: const ValueKey('cell'),
              label: 'Name',
              column: SortColumn.name,
              sortColumn: sortColumn,
              sortDirection: sortDirection,
              onToggleSort: (_) {},
            ),
          ],
        ),
      ),
    ),
  );

  testWidgets('announces the direction of the active column', (tester) async {
    await pumpCell(
      tester,
      sortColumn: SortColumn.name,
      sortDirection: SortDirection.desc,
    );

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(
      tester.getSemantics(find.byKey(const ValueKey('cell'))),
      isSemantics(
        label: 'Name',
        value: 'sorted descending',
        isButton: true,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('an inactive column is just a button', (tester) async {
    await pumpCell(tester, sortColumn: SortColumn.size);

    expect(
      tester.getSemantics(find.byKey(const ValueKey('cell'))),
      isSemantics(label: 'Name', value: '', isButton: true),
    );
  });

  testWidgets('sorts from the keyboard and shows where focus is', (
    tester,
  ) async {
    final toggled = <SortColumn>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.dark(),
        home: Scaffold(
          body: Row(
            children: [
              FileSortHeaderCell(
                key: const ValueKey('cell'),
                label: 'Name',
                column: SortColumn.name,
                sortColumn: SortColumn.size,
                sortDirection: SortDirection.asc,
                onToggleSort: toggled.add,
              ),
            ],
          ),
        ),
      ),
    );

    final cell = find.byKey(const ValueKey('cell'));
    await tabTo(tester, cell);
    expect(
      find.descendant(of: cell, matching: find.byType(QuarkFocusRing)),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(toggled, [SortColumn.name, SortColumn.name]);
  });
}
