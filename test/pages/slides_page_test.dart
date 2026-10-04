import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/slides_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/pages/slides_page.dart';
import 'package:quark/router.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/tap_target_guidelines.dart' as tap;
import '../support/text_scale.dart';

FileNode _node(String path) => FileNode(
  name: path.split('/').last,
  size: 1,
  isDir: false,
  deviceName: '',
  devicePath: '',
  deviceSerial: '',
  dirPath: path,
);

/// The Slides page (#1161): the `.qslide` list, its empty and error states,
/// and starting a new presentation.
void main() {
  late List<FileNode> listing;
  late Object? failure;
  late List<String> created;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    listing = [];
    failure = null;
    created = [];
  });

  SlidesController fakeController() => SlidesController(
    peekSlides: () => null,
    listSlides: () async {
      final f = failure;
      if (f != null) throw f;
      return listing;
    },
    searchContent: (_) async => const [],
    createPresentation: (name) async {
      created.add(name);
      return 'home/ann/$name.qslide';
    },
  );

  Future<GoRouter> visit(WidgetTester tester) async {
    final controller = fakeController();
    addTearDown(controller.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.slides,
      routes: [
        GoRoute(
          path: AppRoutes.slides,
          builder: (_, _) => SlidesPage(controller: controller),
        ),
        GoRoute(
          path: '${AppRoutes.slides}/:path(.*)',
          builder: (_, state) => Text('editor ${state.pathParameters['path']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('shows the empty state with a way to start ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      await visit(tester);
      expect(find.text('No presentations yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('slides_create_cta')), findsOneWidget);
      expect(find.byKey(const ValueKey('slides_new')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);
    });

    testWidgets('lists presentations and opens one at its URL ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      listing = [_node('talks/Pitch.qslide'), _node('Q1 review.qslide')];
      final router = await visit(tester);
      expect(find.text('Pitch'), findsOneWidget);
      expect(find.text('Q1 review'), findsOneWidget);

      await tester.tap(find.text('Pitch'));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/slides/talks/Pitch.qslide',
      );
      expect(find.text('editor talks/Pitch.qslide'), findsOneWidget);
    });
  }

  testWidgets('a search filters by name', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    listing = [_node('Pitch.qslide'), _node('Roadmap.qslide')];
    await visit(tester);
    await tester.enterText(find.byKey(const ValueKey('slides_search')), 'road');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Roadmap'), findsOneWidget);
    expect(find.text('Pitch'), findsNothing);
  });

  testWidgets('New presentation creates one and opens it', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    final router = await visit(tester);
    await tester.tap(find.byKey(const ValueKey('slides_new')));
    await tester.pumpAndSettle();
    expect(find.text('New presentation'), findsWidgets);
    await tester.enterText(find.byType(TextField).last, 'Pitch');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(created, ['Pitch']);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/slides/home/ann/Pitch.qslide',
    );
  });

  testWidgets('a failed listing says so and retries', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    failure = Exception('boom');
    await visit(tester);
    expect(find.text("Couldn't load your presentations."), findsOneWidget);

    failure = null;
    listing = [_node('Pitch.qslide')];
    // The mixin debounces on the wall clock, which the fake one does not move.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.tap(find.byKey(const ValueKey('slides_retry')));
    await tester.pumpAndSettle();
    expect(find.text('Pitch'), findsOneWidget);
  });

  testLargeText('the list fits', (tester, size) async {
    listing = [_node('A very long presentation name for a phone.qslide')];
    await visit(tester);
    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
  });
}
