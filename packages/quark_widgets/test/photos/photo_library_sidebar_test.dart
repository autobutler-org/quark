import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  Widget sidebar({Widget? sizeControl, Widget? categories}) =>
      PhotoLibrarySidebar(
        sizeControl: sizeControl,
        categories: categories,
        albums: const Text('the albums'),
      );

  // Rendered the way the app renders it on a wide window: as a split view's
  // pane. Narrow, the split view stacks it above the grid in a sliver, which
  // hands it unbounded height (#1599).
  Widget inSplitView(Widget child) => QuarkSplitView(
    sidebar: child,
    slivers: const [SliverToBoxAdapter(child: Text('grid'))],
  );

  testBothViewports('lays out inside a split view', (tester, size) async {
    await pumpAt(
      tester,
      inSplitView(
        sidebar(
          sizeControl: const Text('the size control'),
          categories: const Text('the categories'),
        ),
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('the albums'), findsOneWidget);
    expect(find.text('the categories'), findsOneWidget);
    expect(find.text('the size control'), findsOneWidget);
  });

  // A phone shows the sidebar in a picker sheet, without the size control,
  // so only the narrow viewport applies.
  testWidgets('shrink-wraps with only the albums in a sheet', (tester) async {
    await pumpAt(
      tester,
      SingleChildScrollView(child: sidebar()),
      size: narrowViewport,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('the albums'), findsOneWidget);
  });
}
