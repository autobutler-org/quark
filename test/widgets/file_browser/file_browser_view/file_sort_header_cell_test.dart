import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_sort_header_cell.dart';

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
}
