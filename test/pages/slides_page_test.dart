import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/slides_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/pages/slides_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/slides_service.dart';
import 'package:quark/utils/error_text.dart';
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
  late List<String> imports;
  late PowerPointImport imported;
  late Object? importFailure;
  late SlideFilePick? devicePick;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    listing = [];
    failure = null;
    created = [];
    imports = [];
    imported = (path: 'home/ann/Talk.qslide', slides: 3, warnings: const []);
    importFailure = null;
    devicePick = null;
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
    landingFolder: () => 'home/ann',
    listFolder: (path) async => [
      _node('$path/talks/'),
      _node('$path/Talk.pptx'),
      _node('$path/notes.txt'),
    ],
    pickPowerPoint: () async => devicePick,
    uploadPowerPoint: (pick) async {
      imports.add('upload ${pick.name}');
      return 'home/ann/${pick.name}';
    },
    importPowerPoint: (path, {serial}) async {
      imports.add('import $path');
      final f = importFailure;
      if (f != null) throw f;
      return imported;
    },
  );

  Future<GoRouter> visit(
    WidgetTester tester, {
    SlidesController? controller,
  }) async {
    controller ??= fakeController();
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

  group('Import PowerPoint (#1171)', () {
    testWidgets('the chip offers both sources on a wide screen', (
      tester,
    ) async {
      tap.setViewport(tester, tap.wideViewport);
      await visit(tester);
      expect(find.byKey(const ValueKey('app_bar_bottom_menu')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('slides_import')));
      await tester.pumpAndSettle();
      expect(find.text('From your Quark'), findsOneWidget);
      expect(find.text('From this device'), findsOneWidget);
      await tap.expectTapTargetGuidelines(tester);
    });

    testWidgets('a phone collapses it into a labeled Import menu', (
      tester,
    ) async {
      tap.setViewport(tester, tap.narrowViewport);
      await visit(tester);
      expect(find.byKey(const ValueKey('slides_import')), findsNothing);
      expect(find.text('Import'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('app_bar_bottom_menu')));
      await tester.pumpAndSettle();
      expect(find.text('From your Quark'), findsOneWidget);
      expect(find.text('From this device'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);
    });

    testWidgets('from the Quark picks a PowerPoint file, imports it in '
        'place and opens the presentation', (tester) async {
      tap.setViewport(tester, tap.narrowViewport);
      final router = await visit(tester);
      await tester.tap(find.byKey(const ValueKey('app_bar_bottom_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slides_import_from_quark')));
      await tester.pumpAndSettle();

      expect(find.text('Choose a PowerPoint file'), findsOneWidget);
      expect(find.text('notes.txt'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('slides_import_pick_file_Talk.pptx')),
      );
      await tester.pumpAndSettle();

      expect(imports, ['import home/ann/Talk.pptx']);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/slides/home/ann/Talk.qslide',
      );
    });

    testWidgets('from this device uploads, imports, shows what was left out '
        'and then opens the presentation', (tester) async {
      tap.setViewport(tester, tap.wideViewport);
      devicePick = (
        name: 'Talk.pptx',
        length: 1,
        bytes: () => Stream.value([1]),
      );
      imported = (
        path: 'home/ann/Talk.qslide',
        slides: 9,
        warnings: const [
          (slide: 2, message: 'Charts are not imported.'),
          (slide: 5, message: 'Charts are not imported.'),
          (slide: 0, message: 'Animations and transitions are not imported.'),
        ],
      );
      final router = await visit(tester);
      await tester.tap(find.byKey(const ValueKey('slides_import')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slides_import_from_device')));
      await tester.pumpAndSettle();

      expect(imports, ['upload Talk.pptx', 'import home/ann/Talk.pptx']);
      expect(
        find.byKey(const ValueKey('slides_import_summary')),
        findsOneWidget,
      );
      expect(
        find.text('2 kinds of content were left out or simplified'),
        findsOneWidget,
      );
      expect(find.text('Charts are not imported.'), findsOneWidget);
      expect(find.text('Slides 2 and 5'), findsOneWidget);
      expect(find.text('Whole presentation'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/slides',
        reason: 'the summary comes before the presentation opens',
      );

      await tester.tap(
        find.byKey(const ValueKey('slides_import_summary_open')),
      );
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/slides/home/ann/Talk.qslide',
      );
    });

    testWidgets('shows progress while the Quark imports', (tester) async {
      tap.setViewport(tester, tap.wideViewport);
      final gate = Completer<PowerPointImport>();
      final controller = SlidesController(
        peekSlides: () => null,
        listSlides: () async => const [],
        searchContent: (_) async => const [],
        pickPowerPoint: () async =>
            (name: 'Talk.pptx', length: 1, bytes: () => Stream.value([1])),
        uploadPowerPoint: (pick) async => 'home/ann/Talk.pptx',
        importPowerPoint: (path, {serial}) => gate.future,
      );
      await visit(tester, controller: controller);
      await tester.tap(find.byKey(const ValueKey('slides_import')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slides_import_from_device')));
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('slides_import_progress')),
        findsOneWidget,
      );
      expect(find.byType(QuarkLoader), findsOneWidget);
      expect(find.text('Importing Talk.pptx…'), findsOneWidget);
      gate.completeError(Exception('down'));
      await tester.pumpAndSettle();
    });

    testWidgets('a refused import closes the progress and says why', (
      tester,
    ) async {
      tap.setViewport(tester, tap.wideViewport);
      importFailure = const ApiException(400);
      final router = await visit(tester);
      await tester.tap(find.byKey(const ValueKey('slides_import')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slides_import_from_quark')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('slides_import_pick_file_Talk.pptx')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('slides_import_progress')),
        findsNothing,
      );
      expect(find.text(Errors.unreadablePowerPoint), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/slides',
      );
    });

    testWidgets('canceling either picker imports nothing', (tester) async {
      tap.setViewport(tester, tap.wideViewport);
      await visit(tester);
      await tester.tap(find.byKey(const ValueKey('slides_import')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slides_import_from_device')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slides_import')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slides_import_from_quark')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(imports, isEmpty);
    });

    testLargeText('the import summary fits', (tester, size) async {
      devicePick = (
        name: 'Talk.pptx',
        length: 1,
        bytes: () => Stream.value([1]),
      );
      imported = (
        path: 'home/ann/Talk.qslide',
        slides: 40,
        warnings: [
          for (var i = 1; i <= 12; i++)
            (slide: i, message: 'Warning number $i about a slide.'),
        ],
      );
      await visit(tester);
      final phone = find
          .byKey(const ValueKey('app_bar_bottom_menu'))
          .evaluate()
          .isNotEmpty;
      await tester.tap(
        find.byKey(ValueKey(phone ? 'app_bar_bottom_menu' : 'slides_import')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slides_import_from_device')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('slides_import_summary')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expectNoClippedText(tester);
    });
  });
}
