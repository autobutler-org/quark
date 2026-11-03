import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark/widgets/layout/admin_map_card.dart';

import '../../support/tap_target_guidelines.dart' show setViewport;

/// #2484: the legend names each admin surface, marks the one on screen, and
/// links to the rest.
void main() {
  Future<GoRouter> pump(WidgetTester tester, Size size) async {
    setViewport(tester, size);
    final router = GoRouter(
      initialLocation: '/here',
      routes: [
        GoRoute(
          path: '/here',
          builder: (_, _) => const Scaffold(
            body: SingleChildScrollView(
              child: AdminMapCard(here: AdminMapStop.clients),
            ),
          ),
        ),
        GoRoute(
          path: '/:rest(.*)',
          builder: (_, state) => Text('at ${state.uri.path}'),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.byKey(const ValueKey('admin_map')));
    await tester.pumpAndSettle();
    return router;
  }

  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    testWidgets('lists every stop and marks this one at $size', (tester) async {
      await pump(tester, size);
      for (final stop in AdminMapStop.values) {
        expect(find.byKey(ValueKey('admin_map_${stop.name}')), findsOneWidget);
      }
      expect(find.textContaining('You are here'), findsOneWidget);
      final here = tester.widget<ListTile>(
        find.byKey(const ValueKey('admin_map_clients')),
      );
      expect(here.onTap, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a row goes to the page that manages it', (tester) async {
    final router = await pump(tester, const Size(1280, 800));
    await tester.tap(find.byKey(const ValueKey('admin_map_disks')));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoutes.systemTab(SystemTab.storage),
    );
  });
}
