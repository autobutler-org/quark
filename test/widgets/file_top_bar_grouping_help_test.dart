import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_view_chips.dart';
import 'package:quark/widgets/file_browser/file_top_bar/view_grouping_copy.dart';

/// #2037: Files offers List / Grid / **Unified** and never says what Unified
/// means. The word names the mode; nothing named what it does.
void main() {
  Future<void> pumpChips(WidgetTester tester, {required bool unified}) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileTopBarViewChips(
            isGridView: false,
            isUnifiedView: unified,
            onToggleView: () {},
            onToggleUnifiedView: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the unified chip says what it does', (tester) async {
    await pumpChips(tester, unified: true);

    expect(find.text('Unified'), findsOneWidget);
    expect(find.byTooltip(ViewGroupingCopy.unified), findsOneWidget);
  });

  testWidgets('the per-device chip says what it does', (tester) async {
    await pumpChips(tester, unified: false);

    expect(find.text('Per-device'), findsOneWidget);
    expect(find.byTooltip(ViewGroupingCopy.perDevice), findsOneWidget);
  });

  test('the copy names drives, not volumes or namespaces', () {
    for (final line in [ViewGroupingCopy.unified, ViewGroupingCopy.perDevice]) {
      expect(line.toLowerCase(), contains('drive'));
    }
  });
}
