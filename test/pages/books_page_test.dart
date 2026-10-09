import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/books_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/pages/books_page.dart';
import 'package:quark/router.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/tap_target_guidelines.dart' as tap;
import '../support/text_scale.dart';

FileNode _node(String path, {int size = 1}) => FileNode(
  name: path.split('/').last,
  size: size,
  isDir: false,
  deviceName: '',
  devicePath: '',
  deviceSerial: '',
  dirPath: path,
);

/// The Books page (#1678): every PDF and EPUB the Quark found, its empty and
/// error states, and opening one in the file viewer.
void main() {
  late List<FileNode> listing;
  late Object? failure;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    listing = [];
    failure = null;
  });

  Future<GoRouter> visit(WidgetTester tester) async {
    final controller = BooksController(
      listBooks: () async {
        final f = failure;
        if (f != null) throw f;
        return listing;
      },
    );
    addTearDown(controller.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.books,
      routes: [
        GoRoute(
          path: AppRoutes.books,
          builder: (_, _) => BooksPage(controller: controller),
        ),
        GoRoute(
          path: '${AppRoutes.viewFile}/:path(.*)',
          builder: (_, state) => Text('viewer ${state.pathParameters['path']}'),
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
    testWidgets('a Quark with no books says so ($name)', (tester) async {
      tap.setViewport(tester, size);
      await visit(tester);
      expect(find.text('No books yet'), findsOneWidget);
      expect(find.byType(QuarkLoader), findsNothing);
      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);
    });

    testWidgets('lists books and opens one in the viewer ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      listing = [
        _node('library/sci fi/Dune.epub', size: 2048),
        _node('Manual.pdf'),
      ];
      final router = await visit(tester);
      expect(find.text('Dune.epub'), findsOneWidget);
      expect(find.text('library/sci fi · 2.0 KB'), findsOneWidget);
      expect(find.text('Manual.pdf'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);

      await tester.tap(
        find.byKey(const ValueKey('book_tile_library/sci fi/Dune.epub')),
      );
      await tester.pumpAndSettle();
      // The viewer's URL says it was opened from Books, so closing it comes
      // back here rather than to the book's folder.
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/view/library/sci%20fi/Dune.epub?from=/books',
      );
      expect(find.text('viewer library/sci fi/Dune.epub'), findsOneWidget);
    });
  }

  testWidgets('a failed listing says so and retries', (tester) async {
    tap.setViewport(tester, tap.narrowViewport);
    failure = Exception('boom');
    await visit(tester);
    expect(find.text("Couldn't load your books."), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);

    failure = null;
    listing = [_node('Manual.pdf')];
    // The mixin debounces on the wall clock, which the fake one does not move.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.tap(find.byKey(const ValueKey('slides_retry')));
    await tester.pumpAndSettle();
    expect(find.text('Manual.pdf'), findsOneWidget);
  });

  testWidgets('the app bar refresh fetches the list again', (tester) async {
    tap.setViewport(tester, tap.narrowViewport);
    await visit(tester);
    expect(find.text('No books yet'), findsOneWidget);

    listing = [_node('Manual.pdf')];
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.tap(find.byType(RefreshIconButton));
    await tester.pumpAndSettle();
    expect(find.text('Manual.pdf'), findsOneWidget);
  });

  testLargeText('the list fits', (tester, size) async {
    listing = [_node('deep/folder/A very long book title for a phone.epub')];
    await visit(tester);
    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
  });
}
