import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_breadcrumb.dart';

import '../../../support/tap_target_guidelines.dart';

/// #2010: home opens the landing folder, so once there it must stop looking
/// and behaving like a button — no handler, no pointer cursor.
void main() {
  Future<List<String>> pumpCrumb(
    WidgetTester tester, {
    required String currentPath,
    required String rootPath,
    double width = 600,
  }) async {
    final events = <String>[];
    final menu = MenuController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: FileTopBarBreadcrumb(
                currentPath: currentPath,
                rootPath: rootPath,
                navEnabled: true,
                hiddenCrumbsController: menu,
                onGoHome: () => events.add('home'),
                onPathSelected: events.add,
              ),
            ),
          ),
        ),
      ),
    );
    return events;
  }

  MouseCursor homeCursor(WidgetTester tester) => tester
      .widget<MouseRegion>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('file_top_bar_home')),
              matching: find.byType(MouseRegion),
            )
            .first,
      )
      .cursor;

  for (final (label, current, root) in [
    ('the real root', '', ''),
    ('a member home', '/users/alice', '/users/alice'),
  ]) {
    testWidgets('home is inert at $label', (tester) async {
      final events = await pumpCrumb(
        tester,
        currentPath: current,
        rootPath: root,
      );

      await tester.tap(find.byKey(const ValueKey('file_top_bar_home')));
      await tester.pump();

      expect(events, isEmpty);
      expect(homeCursor(tester), SystemMouseCursors.basic);
    });
  }

  testWidgets('home still goes home from a folder', (tester) async {
    final events = await pumpCrumb(
      tester,
      currentPath: '/users/alice/photos',
      rootPath: '/users/alice',
    );

    await tester.tap(find.byKey(const ValueKey('file_top_bar_home')));
    await tester.pump();

    expect(events, ['home']);
    expect(homeCursor(tester), SystemMouseCursors.click);
  });

  // #2603, #2605: home, the hidden-ancestors button and every ancestor are
  // labeled 48dp targets, while the pill keeps the height of a bar button.
  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';
    testWidgets('every crumb is a labeled 48dp target ($label)', (
      tester,
    ) async {
      setViewport(tester, size);
      final events = await pumpCrumb(
        tester,
        currentPath: '/photos/2024/summer/beach/day-one/morning',
        rootPath: '',
        width: size.width - 40,
      );

      final home = find.byKey(const ValueKey('file_top_bar_home'));
      expect(tester.getSize(home).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(home).height, greaterThanOrEqualTo(48));
      expect(find.byTooltip('Go to the top folder'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('file_top_bar_pill'))).height,
        lessThanOrEqualTo(36),
      );
      if (size == narrowViewport) {
        expect(find.byTooltip('Show hidden folders'), findsOneWidget);
      }

      // A tap in home's margin, clear of the 16px glyph, still lands.
      await tester.tapAt(tester.getTopLeft(home) + const Offset(2, 2));
      expect(events, ['home']);

      await expectTapTargetGuidelines(tester);
    });
  }
}
