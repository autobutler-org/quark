import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_breadcrumb.dart';

/// #2010: home opens the landing folder, so once there it must stop looking
/// and behaving like a button — no handler, no pointer cursor.
void main() {
  Future<List<String>> pumpCrumb(
    WidgetTester tester, {
    required String currentPath,
    required String rootPath,
  }) async {
    final events = <String>[];
    final menu = MenuController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
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
}
