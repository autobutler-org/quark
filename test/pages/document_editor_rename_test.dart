import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/document_editor_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secure_storage.dart';
import '../support/tap_target_guidelines.dart' show setViewport;

/// #2107: the title of an open document renames the file, as a sheet's does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(mockSecureStorage);

  /// Makes the editor's save upload fail as a refused connection would.
  var refuseUploads = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    await AppSettings.instance.addHost(
      HostEntry(name: 'Test', hostAddress: 'http://localhost:8080'),
    );
    await AppSettings.instance.setSessionToken('a-token');
    final doc = jsonEncode({
      'ops': [
        {'insert': 'Hello\n'},
      ],
    });
    refuseUploads = false;
    sharedHttpClientFactory = () => MockClient((request) async {
      if (refuseUploads &&
          request.url.path.startsWith('/api/v0/files/upload')) {
        throw http.ClientException('refused');
      }
      // The editor downloads the doc and, to rename it, lists its folder.
      if (request.url.path.endsWith('/download')) {
        return http.Response(doc, 200);
      }
      if (request.method == 'GET') return http.Response('[]', 200);
      return http.Response('{}', 200);
    });
    resetSharedHttpClient();
  });

  tearDown(() async {
    sharedHttpClientFactory = buildLocalTrustHttpClient;
    resetSharedHttpClient();
    await AppSettings.instance.setSessionToken(null);
  });

  String location(GoRouter router) =>
      router.routeInformationProvider.value.uri.toString();

  Future<GoRouter> pumpRoutedEditor(
    WidgetTester tester, {
    String location = '/docs/reports/budget.qdoc',
  }) async {
    setViewport(tester, const Size(1280, 800));
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '${AppRoutes.docs}/:path(.*)',
          builder: (_, state) => DocumentEditorPage(
            filePath: state.pathParameters['path'] ?? '',
            deviceSerial: state.uri.queryParameters['serial'] ?? '',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates:
            FlutterQuillLocalizations.localizationsDelegates,
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('the title offers rename, and cancel leaves the doc', (
    tester,
  ) async {
    final router = await pumpRoutedEditor(tester);

    expect(find.byKey(const ValueKey('doc_rename_title')), findsOneWidget);
    expect(find.byTooltip('Rename'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('doc_rename_title')));
    await tester.pumpAndSettle();
    expect(find.text('Rename document'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Rename document'), findsNothing);
    expect(location(router), AppRoutes.docFile('reports/budget.qdoc'));
    expect(find.text('budget'), findsOneWidget);
  });

  testWidgets('renaming the title follows the new name', (tester) async {
    final router = await pumpRoutedEditor(tester);

    await tester.tap(find.byKey(const ValueKey('doc_rename_title')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'forecast',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(location(router), AppRoutes.docFile('reports/forecast.qdoc'));
    expect(find.text('forecast'), findsOneWidget);
    expect(find.text('budget'), findsNothing);
  });

  testWidgets('renaming keeps the page the doc was opened from (#2403)', (
    tester,
  ) async {
    final router = await pumpRoutedEditor(
      tester,
      location: '/docs/reports/budget.qdoc?from=/docs',
    );

    await tester.tap(find.byKey(const ValueKey('doc_rename_title')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'forecast',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(location(router), '/docs/reports/forecast.qdoc?from=/docs');
  });

  testWidgets('a failed save does not rename', (tester) async {
    final router = await pumpRoutedEditor(tester);
    refuseUploads = true;

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    tester
        .widget<QuillEditor>(find.byType(QuillEditor))
        .controller
        .document
        .insert(0, 'x');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('doc_rename_title')));
    await tester.pumpAndSettle();

    expect(find.text('Rename document'), findsNothing);
    expect(
      find.text(
        Errors.message(http.ClientException('refused'), 'save the document'),
      ),
      findsOneWidget,
    );
    expect(location(router), AppRoutes.docFile('reports/budget.qdoc'));
  });
}
