import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/pages/document_editor_page.dart';
import 'package:quark/pages/plaintext_editor_page.dart';
import 'package:quark/pages/spreadsheet_editor_page.dart';
import 'package:quark/router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #1749: closing a doc or a sheet that lives inside a folder dropped the user
/// in the home folder. The editor routes were declared as children of `/docs`
/// and `/sheets`, so go_router built the section list underneath every editor
/// and "back" answered with a page the user had never visited; the plaintext
/// editor spelled the same mistake out, sending its no-history case to
/// [AppRoutes.files] by name.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AppRoutes.containingFolder', () {
    test('is the folder holding a nested file', () {
      expect(
        AppRoutes.containingFolder('reports/2024/q1.qdoc'),
        '/files/reports/2024',
      );
    });

    test('tolerates the leading slash the file browser passes', () {
      expect(AppRoutes.containingFolder('/reports/q1.qdoc'), '/files/reports');
    });

    test('is the home folder only for a file that really sits there', () {
      expect(AppRoutes.containingFolder('q1.qdoc'), AppRoutes.files);
    });

    test('encodes the folder name, as every other route builder does', () {
      expect(
        AppRoutes.containingFolder('my reports/q1.qdoc'),
        '/files/my%20reports',
      );
    });
  });

  /// The real editor routes over a stub file browser, so the test drives the
  /// actual declarations in [AppRoutes] rather than a copy of them.
  Future<GoRouter> pumpEditors(
    WidgetTester tester, {
    required String initialLocation,
  }) async {
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: AppRoutes.files,
          builder: (_, _) => const Scaffold(body: Text('files')),
        ),
        GoRoute(
          path: '${AppRoutes.files}/:path(.*)',
          builder: (_, state) =>
              Scaffold(body: Text('folder:${state.pathParameters['path']}')),
        ),
        GoRoute(
          path: AppRoutes.docs,
          builder: (_, _) => const Scaffold(body: Text('docs list')),
        ),
        GoRoute(
          path: '${AppRoutes.docs}/:path(.*)',
          builder: (_, state) =>
              DocumentEditorPage(filePath: state.pathParameters['path'] ?? ''),
        ),
        GoRoute(
          path: AppRoutes.sheets,
          builder: (_, _) => const Scaffold(body: Text('sheets list')),
        ),
        GoRoute(
          path: '${AppRoutes.sheets}/:path(.*)',
          builder: (_, state) => SpreadsheetEditorPage(
            filePath: state.pathParameters['path'] ?? '',
          ),
        ),
        GoRoute(
          path: '${AppRoutes.plaintextEditor}/:path(.*)',
          builder: (_, state) =>
              PlaintextEditorPage(filePath: state.pathParameters['path'] ?? ''),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  group('back from a deep-linked editor lands in the containing folder', () {
    // The reported bug: every one of these used to end up on /files.
    for (final entry in const {
      'doc': '/docs/reports/2024/q1.qdoc',
      'sheet': '/sheets/reports/2024/budget.qsheet',
      'plaintext': '/edit/reports/2024/notes.txt',
    }.entries) {
      testWidgets('${entry.key} editor', (tester) async {
        final router = await pumpEditors(tester, initialLocation: entry.value);

        // Nothing was pushed underneath, so the editor has to supply its own
        // way out — without one the user is stranded (the old nested routes
        // supplied the section list instead).
        expect(find.byType(BackButton), findsOneWidget);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();

        expect(
          router.routeInformationProvider.value.uri.toString(),
          '/files/reports/2024',
        );
        expect(find.text('folder:reports/2024'), findsOneWidget);
      });
    }
  });

  group('system back from an editor with nothing underneath', () {
    // Every entry point now opens an editor at its own URL (#2078, #2081), so
    // a system back that closed the app would be the common case, not a
    // deep-link corner.
    for (final entry in const {
      'doc': '/docs/reports/2024/q1.qdoc',
      'sheet': '/sheets/reports/2024/budget.qsheet',
      'plaintext': '/edit/reports/2024/notes.txt',
    }.entries) {
      testWidgets('${entry.key} editor lands in the containing folder', (
        tester,
      ) async {
        final router = await pumpEditors(tester, initialLocation: entry.value);

        final handled = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(handled, isTrue, reason: 'the app must not close');
        expect(
          router.routeInformationProvider.value.uri.toString(),
          '/files/reports/2024',
        );
      });
    }
  });

  // #2403: the Docs and Sheets lists open an editor with `go`, so nothing is
  // underneath it to pop back to, and its way out answered with the containing
  // folder whoever had opened it. The URL now says where it was opened from.
  group('back from an editor returns to the page that opened it', () {
    for (final entry in const {
      'doc opened from Docs': (
        '/docs/reports/2024/q1.qdoc?from=/docs',
        '/docs',
        'docs list',
      ),
      'sheet opened from Sheets': (
        '/sheets/reports/2024/budget.qsheet?from=/sheets',
        '/sheets',
        'sheets list',
      ),
      'sheet found by a search on Docs': (
        '/sheets/reports/2024/budget.qsheet?from=/docs',
        '/docs',
        'docs list',
      ),
      'doc opened from a folder it is not in': (
        '/docs/reports/2024/q1.qdoc?from=/files/shared',
        '/files/shared',
        'folder:shared',
      ),
    }.entries) {
      final (opened, origin, page) = entry.value;

      testWidgets('${entry.key}, by the back button', (tester) async {
        final router = await pumpEditors(tester, initialLocation: opened);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();

        expect(router.routeInformationProvider.value.uri.toString(), origin);
        expect(find.text(page), findsOneWidget);
      });

      testWidgets('${entry.key}, by a system back', (tester) async {
        final router = await pumpEditors(tester, initialLocation: opened);

        final handled = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(handled, isTrue, reason: 'the app must not close');
        expect(router.routeInformationProvider.value.uri.toString(), origin);
      });
    }

    // The origin arrives in a URL anyone can write, so only a path inside the
    // app counts; anything else is the deep link it looks like.
    for (final from in const [
      'https://example.com/',
      '//example.com/docs',
      'docs',
      '',
    ]) {
      testWidgets('an origin of "$from" is ignored', (tester) async {
        final router = await pumpEditors(
          tester,
          initialLocation:
              '/docs/reports/2024/q1.qdoc'
              '?from=${Uri.encodeQueryComponent(from)}',
        );

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();

        expect(
          router.routeInformationProvider.value.uri.toString(),
          '/files/reports/2024',
        );
      });
    }
  });
}
