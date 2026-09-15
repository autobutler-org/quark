import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Every top-level page opens this one drawer, so what it offers and where
/// each row goes is decided here once (#1662).
void main() {
  final scaffoldKey = GlobalKey<ScaffoldState>();

  Widget page(String name, QuarkDrawerSection section) => Scaffold(
    key: name == 'files' ? scaffoldKey : null,
    drawer: AppDrawer(activeSection: section),
    body: Text('$name page'),
  );

  Future<void> pumpDrawer(WidgetTester tester) async {
    // Tall enough that the drawer's lazy list builds every row.
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: AppRoutes.files,
      routes: [
        GoRoute(
          path: AppRoutes.files,
          builder: (_, _) => page('files', QuarkDrawerSection.files),
        ),
        GoRoute(
          path: AppRoutes.photos,
          builder: (_, _) => page('photos', QuarkDrawerSection.photos),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
  }

  testWidgets('offers every page and marks the one it was opened from', (
    tester,
  ) async {
    await pumpDrawer(tester);

    for (final section in [
      QuarkDrawerSection.files,
      QuarkDrawerSection.photos,
      QuarkDrawerSection.trash,
      QuarkDrawerSection.docs,
      QuarkDrawerSection.sheets,
      QuarkDrawerSection.devices,
      QuarkDrawerSection.health,
      QuarkDrawerSection.vault,
      QuarkDrawerSection.jobs,
      QuarkDrawerSection.settings,
    ]) {
      expect(
        find.byKey(ValueKey('drawer_${section.name}')),
        findsOneWidget,
        reason: '${section.name} is missing',
      );
    }
    final files = tester.widget<ListTile>(
      find.byKey(const ValueKey('drawer_files')),
    );
    expect(files.selected, isTrue);
  });

  testWidgets('a row goes to its page', (tester) async {
    await pumpDrawer(tester);

    await tester.tap(find.byKey(const ValueKey('drawer_photos')));
    await tester.pumpAndSettle();

    expect(find.text('photos page'), findsOneWidget);
    expect(find.text('files page'), findsNothing);
  });

  testWidgets('the current page closes the drawer and stays put', (
    tester,
  ) async {
    await pumpDrawer(tester);

    await tester.tap(find.byKey(const ValueKey('drawer_files')));
    await tester.pumpAndSettle();

    expect(scaffoldKey.currentState!.isDrawerOpen, isFalse);
    expect(find.text('files page'), findsOneWidget);
  });
}
