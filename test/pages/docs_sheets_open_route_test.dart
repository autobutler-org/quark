import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/docs_page.dart';
import 'package:quark/pages/sheets_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/widgets/content_result_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #2081: a sheet opened from the Sheets list was pushed, and a push does not
/// change the address bar, so a reload read `/sheets` and reopened the list.
/// The Docs list had the same defect. A file opened from either list must be
/// at its own URL.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      if (request.url.path == '/api/v0/files/search/content') {
        return http.Response(
          jsonEncode([
            {'serial': '', 'relPath': 'notes/plan.qsheet', 'snippet': 'q3'},
          ]),
          200,
        );
      }
      if (request.url.path != '/api/v0/files/by-type') {
        return http.Response('[]', 200);
      }
      final type = request.url.queryParameters['fileType'];
      return http.Response(
        jsonEncode([
          {
            'name': 'budget.$type',
            'size': 1,
            'isDir': false,
            'dirPath': 'reports/budget.$type',
            'fileType': type,
          },
        ]),
        200,
      );
    });
  });

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  Future<GoRouter> pumpList(WidgetTester tester, String list) async {
    final router = GoRouter(
      initialLocation: list,
      routes: [
        GoRoute(path: AppRoutes.sheets, builder: (_, _) => const SheetsPage()),
        GoRoute(path: AppRoutes.docs, builder: (_, _) => const DocsPage()),
        GoRoute(
          path: '${AppRoutes.sheets}/:path(.*)',
          builder: (_, state) =>
              Text('sheet editor ${state.pathParameters['path']}'),
        ),
        GoRoute(
          path: '${AppRoutes.docs}/:path(.*)',
          builder: (_, state) =>
              Text('doc editor ${state.pathParameters['path']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  String location(GoRouter router) =>
      router.routeInformationProvider.value.uri.toString();

  testWidgets('a sheet opened from the Sheets list is at its own URL', (
    tester,
  ) async {
    final router = await pumpList(tester, AppRoutes.sheets);

    await tester.tap(find.text('budget'));
    await tester.pumpAndSettle();

    // The list it was opened from rides along, so back returns there (#2403).
    expect(location(router), '/sheets/reports/budget.qsheet?from=/sheets');
    expect(find.text('sheet editor reports/budget.qsheet'), findsOneWidget);
  });

  testWidgets('a doc opened from the Docs list is at its own URL', (
    tester,
  ) async {
    final router = await pumpList(tester, AppRoutes.docs);

    await tester.tap(find.text('budget'));
    await tester.pumpAndSettle();

    expect(location(router), '/docs/reports/budget.qdoc?from=/docs');
    expect(find.text('doc editor reports/budget.qdoc'), findsOneWidget);
  });

  // A hit's extension picks its editor (#2259), so the editor cannot tell
  // which list the search was on; the URL has to (#2403).
  testWidgets('a search hit opens saying which list it was found on', (
    tester,
  ) async {
    final router = await pumpList(tester, AppRoutes.docs);

    await tester.enterText(find.byType(TextField), 'plan');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ContentResultTile));
    await tester.pumpAndSettle();

    expect(location(router), '/sheets/notes/plan.qsheet?from=/docs');
    expect(find.text('sheet editor notes/plan.qsheet'), findsOneWidget);
  });
}
