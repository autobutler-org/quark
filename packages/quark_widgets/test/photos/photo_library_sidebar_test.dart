import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  Widget sidebar({
    int columns = 4,
    int minColumns = 1,
    int maxColumns = 8,
    List<int>? changes,
    Widget? categories,
  }) => PhotoLibrarySidebar(
    columns: columns,
    minColumns: minColumns,
    maxColumns: maxColumns,
    onColumnsChanged: (c) => changes?.add(c),
    categories: categories,
    albums: const Text('the albums'),
  );

  // Rendered the way the app renders it: inside a QuarkSplitView, which is
  // what hands it unbounded height below the breakpoint (#1599).
  Widget inSplitView(Widget child) => QuarkSplitView(
    sidebar: child,
    slivers: const [SliverToBoxAdapter(child: Text('grid'))],
  );

  testBothViewports('lays out inside a split view', (tester, size) async {
    await pumpAt(
      tester,
      inSplitView(sidebar(categories: const Text('the categories'))),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('the albums'), findsOneWidget);
    expect(find.text('the categories'), findsOneWidget);
    expect(find.byKey(const ValueKey('photo_columns_slider')), findsOneWidget);
  });

  testBothViewports('steps the column count within its bounds', (
    tester,
    size,
  ) async {
    final changes = <int>[];
    await pumpAt(tester, inSplitView(sidebar(changes: changes)), size: size);

    await tester.tap(find.byKey(const ValueKey('photo_columns_less')));
    await tester.tap(find.byKey(const ValueKey('photo_columns_more')));

    expect(changes, [3, 5]);
  });

  testBothViewports('disables the step past either bound', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      inSplitView(sidebar(columns: 12, minColumns: 3, maxColumns: 3)),
      size: size,
    );

    IconButton button(String key) =>
        tester.widget<IconButton>(find.byKey(ValueKey(key)));
    expect(button('photo_columns_less').onPressed, isNull);
    expect(button('photo_columns_more').onPressed, isNull);
  });
}
