import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_nav_buttons.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_path_row.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_search_area.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/file_top_bar.dart';
import '../../../support/tap_target_guidelines.dart'
    show narrowViewport, setViewport, wideViewport;

// #4226: a phone had two rows of icons above the first file, and the second
// repeated what the bar already had. Compact, the bar is one row: the brand,
// Search and Select. The path and the sort sit over the list instead.
void main() {
  Future<void> pumpBar(
    WidgetTester tester,
    Size size, {
    bool isSearchMode = false,
    VoidCallback? onSearchOpened,
  }) async {
    setViewport(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: testFileTopBar(
            compact: true,
            isSearchMode: isSearchMode,
            onStartSelection: () {},
            onSearchOpened: onSearchOpened,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';

    testWidgets('one row with Search and Select ($label)', (tester) async {
      await pumpBar(tester, size);

      expect(find.byType(FileTopBarPathRow), findsNothing);
      expect(find.byType(FileTopBarNavButtons), findsNothing);
      expect(find.byKey(const ValueKey('file_top_bar_search')), findsOneWidget);
      expect(find.byTooltip('Select'), findsOneWidget);
      expect(tester.getSize(find.byType(QuarkAppBar)).height, kToolbarHeight);
      expect(tester.takeException(), isNull);
    });

    testWidgets('search opens a second row for the field ($label)', (
      tester,
    ) async {
      await pumpBar(tester, size, isSearchMode: true);

      expect(find.byType(FileTopBarSearchArea), findsOneWidget);
      expect(
        tester.getSize(find.byType(QuarkAppBar)).height,
        kToolbarHeight + QuarkAppBarBottom.height,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('tapping Search tells the page the field is open', (
    tester,
  ) async {
    var opened = 0;
    await pumpBar(tester, narrowViewport, onSearchOpened: () => opened++);

    await tester.tap(find.byKey(const ValueKey('file_top_bar_search')));
    await tester.pump();

    expect(opened, 1);
  });
}
