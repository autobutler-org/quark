import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_view_chips.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_views_menu.dart';
import 'package:quark/widgets/file_browser/file_top_bar/view_grouping_copy.dart';

import '../support/tap_target_guidelines.dart' show setViewport;
import '../support/text_scale.dart' show narrowViewport;

/// #2037: Files offers List / Grid / **Unified** and never says what Unified
/// means. The word names the mode; nothing named what it does.
void main() {
  Future<void> pumpChips(WidgetTester tester, {required bool unified}) async {
    setViewport(tester, const Size(1200, 800));

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

  /// #1871: an (i) beside the toggle explains both views and the device tags.
  Future<void> expectHelpOpens(WidgetTester tester) async {
    const help = ValueKey('file_top_bar_grouping_help');
    expect(find.byKey(help), findsOneWidget);
    await tester.tap(find.byKey(help));
    await tester.pumpAndSettle();

    expect(find.text(ViewGroupingCopy.helpTitle), findsOneWidget);
    for (final topic in ViewGroupingCopy.helpTopics) {
      expect(find.text(topic.heading), findsWidgets);
      expect(find.text(topic.body), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  }

  testWidgets('the wide bar has an (i) that explains the views', (
    tester,
  ) async {
    await pumpChips(tester, unified: true);
    await expectHelpOpens(tester);
  });

  testWidgets('the compact Views menu has the same (i)', (tester) async {
    setViewport(tester, narrowViewport);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FileTopBarViewsMenu(
              isGridView: false,
              isUnifiedView: true,
              onToggleView: () {},
              onToggleUnifiedView: () {},
            ),
          ),
        ),
      ),
    );
    await expectHelpOpens(tester);
  });

  test('the copy names drives, not volumes or namespaces', () {
    for (final line in [
      ViewGroupingCopy.unified,
      ViewGroupingCopy.perDevice,
      for (final topic in ViewGroupingCopy.helpTopics) topic.body,
    ]) {
      expect(line.toLowerCase(), contains('drive'));
    }
  });
}
