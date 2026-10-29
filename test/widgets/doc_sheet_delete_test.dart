import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/controllers/file_type_listing_cache.dart';
import 'package:quark/controllers/slides_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/pages/docs_page.dart';
import 'package:quark/pages/sheets_page.dart';
import 'package:quark/pages/slides_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/slides_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secure_storage.dart';

/// #3339: the Docs, Sheets and Slides row menu moves a file to Trash, and
/// only when the signed-in account can write that path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var deleteStatus = 200;
  final requests = <http.Request>[];

  Map<String, Object> file(String path, {String serial = '', String? type}) {
    final name = path.split('/').last;
    return {
      'name': name,
      'size': 1,
      'isDir': false,
      'dirPath': path,
      'deviceSerial': serial,
      'deviceName': serial.isEmpty ? 'Data' : 'USB',
      'fileType': type ?? name.split('.').last,
    };
  }

  setUp(() async {
    mockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    AppSettings.instance.isAdmin.value = false;
    FileTypeListingCache.instance.clear();
    deleteStatus = 200;
    requests.clear();
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      if (request.method == 'DELETE') {
        return http.Response('', deleteStatus);
      }
      if (request.url.path != '/api/v0/files/by-type') {
        return http.Response('[]', 200);
      }
      final type = request.url.queryParameters['fileType'];
      final listed = switch (type) {
        'qdoc' => [
          file('notes/hello.qdoc', serial: 'USB9', type: 'qdoc'),
          file('users/alice/home.qdoc', type: 'qdoc'),
          file('shared.qdoc', type: 'qdoc'),
        ],
        'qsheet' => [
          file('budget.qsheet', type: 'qsheet'),
          file('users/alice/mine.qsheet', type: 'qsheet'),
        ],
        _ => const <Map<String, Object>>[],
      };
      return http.Response(jsonEncode(listed), 200);
    });
  });

  tearDown(() async {
    AppSettings.instance.isAdmin.value = false;
    FileTypeListingCache.instance.clear();
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  Future<void> signInAs(String username) async {
    await AppSettings.instance.addHost(
      HostEntry(name: 'Test', hostAddress: 'http://localhost:8080'),
    );
    await AppSettings.instance.setUsername(username);
  }

  Future<void> openMenu(WidgetTester tester, String path) async {
    await tester.tap(find.byKey(ValueKey('doc_sheet_menu_$path')));
    await tester.pumpAndSettle();
  }

  Finder deleteOf(String path) =>
      find.byKey(ValueKey('doc_sheet_delete_$path'));

  Future<void> confirmTrash(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Move to Trash'));
    await tester.pumpAndSettle();
  }

  http.Request? deletedRequest() => requests
      .where(
        (request) =>
            request.method == 'DELETE' && request.url.path == '/api/v0/files',
      )
      .firstOrNull;

  Future<GoRouter> visit(WidgetTester tester, String location) async {
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(path: AppRoutes.docs, builder: (_, _) => const DocsPage()),
        GoRoute(path: AppRoutes.sheets, builder: (_, _) => const SheetsPage()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('Docs deletes on the file\'s own device after a confirmation', (
    tester,
  ) async {
    AppSettings.instance.isAdmin.value = true;
    await visit(tester, AppRoutes.docs);
    await openMenu(tester, 'notes/hello.qdoc');
    expect(deleteOf('notes/hello.qdoc'), findsOneWidget);

    await tester.tap(deleteOf('notes/hello.qdoc'));
    await tester.pumpAndSettle();
    expect(find.text('Move to Trash?'), findsOneWidget);
    expect(deletedRequest(), isNull);

    await confirmTrash(tester);
    final request = deletedRequest()!;
    expect(request.url.queryParameters['rootDir'], 'notes');
    expect(request.url.queryParameters['filePaths'], 'hello.qdoc');
    expect(request.url.queryParameters['serial'], 'USB9');
    expect(find.text('Deleted'), findsOneWidget);
  });

  testWidgets('Docs leaves a file alone when the confirmation is canceled', (
    tester,
  ) async {
    AppSettings.instance.isAdmin.value = true;
    await visit(tester, AppRoutes.docs);
    await openMenu(tester, 'notes/hello.qdoc');
    await tester.tap(deleteOf('notes/hello.qdoc'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(deletedRequest(), isNull);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('Docs says when the Quark refuses the delete', (tester) async {
    AppSettings.instance.isAdmin.value = true;
    deleteStatus = 403;
    await visit(tester, AppRoutes.docs);
    await openMenu(tester, 'notes/hello.qdoc');
    await tester.tap(deleteOf('notes/hello.qdoc'));
    await tester.pumpAndSettle();
    await confirmTrash(tester);

    expect(
      find.text("You don't have permission to delete the document."),
      findsOneWidget,
    );
    expect(find.text('Deleted'), findsNothing);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('a member deletes a doc in their home and not one outside it', (
    tester,
  ) async {
    await signInAs('alice');
    await visit(tester, AppRoutes.docs);

    await openMenu(tester, 'users/alice/home.qdoc');
    expect(deleteOf('users/alice/home.qdoc'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
    await tester.tapAt(const Offset(5, 500));
    await tester.pumpAndSettle();

    await openMenu(tester, 'shared.qdoc');
    expect(deleteOf('shared.qdoc'), findsNothing);
    expect(find.text('Rename'), findsOneWidget);
  });

  testWidgets('Docs shows Delete once the account is known to be an admin', (
    tester,
  ) async {
    await visit(tester, AppRoutes.docs);
    await openMenu(tester, 'shared.qdoc');
    expect(deleteOf('shared.qdoc'), findsNothing);
    await tester.tapAt(const Offset(5, 500));
    await tester.pumpAndSettle();

    AppSettings.instance.isAdmin.value = true;
    await tester.pumpAndSettle();
    await openMenu(tester, 'shared.qdoc');
    expect(deleteOf('shared.qdoc'), findsOneWidget);
  });

  testWidgets('Sheets deletes a spreadsheet the account can write', (
    tester,
  ) async {
    AppSettings.instance.isAdmin.value = true;
    await visit(tester, AppRoutes.sheets);
    await openMenu(tester, 'budget.qsheet');
    await tester.tap(deleteOf('budget.qsheet'));
    await tester.pumpAndSettle();
    await confirmTrash(tester);

    final request = deletedRequest()!;
    expect(request.url.queryParameters['filePaths'], 'budget.qsheet');
    expect(request.url.queryParameters['rootDir'], '');
    expect(request.url.queryParameters.containsKey('serial'), isFalse);
  });

  testWidgets('a member does not see Delete on a sheet outside their home', (
    tester,
  ) async {
    await signInAs('alice');
    await visit(tester, AppRoutes.sheets);

    await openMenu(tester, 'budget.qsheet');
    expect(deleteOf('budget.qsheet'), findsNothing);
    expect(find.text('Rename'), findsOneWidget);
    await tester.tapAt(const Offset(5, 500));
    await tester.pumpAndSettle();

    await openMenu(tester, 'users/alice/mine.qsheet');
    expect(deleteOf('users/alice/mine.qsheet'), findsOneWidget);
  });

  group('Slides', () {
    FileNode node(String path, {String serial = ''}) => FileNode(
      name: path.split('/').last,
      size: 1,
      isDir: false,
      deviceName: serial.isEmpty ? 'Data' : 'USB',
      devicePath: '',
      deviceSerial: serial,
      dirPath: path,
    );

    Future<void> visitSlides(WidgetTester tester, List<FileNode> files) async {
      final controller = SlidesController(
        peekSlides: () => null,
        listSlides: () async => files,
        searchContent: (_) async => const [],
        createPresentation: (_) async => 'talk.qslide',
        landingFolder: () => '',
        listFolder: (_) async => const [],
        pickPowerPoint: () async => null,
        uploadPowerPoint: (_) async => '',
        importPowerPoint: (path, {serial}) async => (
          path: path,
          slides: 1,
          warnings: const <PowerPointImportWarning>[],
        ),
      );
      addTearDown(controller.dispose);
      final router = GoRouter(
        initialLocation: AppRoutes.slides,
        routes: [
          GoRoute(
            path: AppRoutes.slides,
            builder: (_, _) => SlidesPage(controller: controller),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
    }

    testWidgets('deletes on the presentation\'s own device', (tester) async {
      AppSettings.instance.isAdmin.value = true;
      await visitSlides(tester, [node('decks/Pitch.qslide', serial: 'USB9')]);
      await openMenu(tester, 'decks/Pitch.qslide');
      expect(find.text('Share'), findsOneWidget);
      await tester.tap(deleteOf('decks/Pitch.qslide'));
      await tester.pumpAndSettle();
      expect(find.text('Move to Trash?'), findsOneWidget);
      await confirmTrash(tester);

      final request = deletedRequest()!;
      expect(request.url.queryParameters['rootDir'], 'decks');
      expect(request.url.queryParameters['filePaths'], 'Pitch.qslide');
      expect(request.url.queryParameters['serial'], 'USB9');
    });

    testWidgets('a member deletes a presentation only in their home', (
      tester,
    ) async {
      await signInAs('alice');
      await visitSlides(tester, [
        node('users/alice/Talk.qslide'),
        node('shared/Talk.qslide'),
      ]);

      await openMenu(tester, 'users/alice/Talk.qslide');
      expect(deleteOf('users/alice/Talk.qslide'), findsOneWidget);
      await tester.tapAt(const Offset(5, 500));
      await tester.pumpAndSettle();

      await openMenu(tester, 'shared/Talk.qslide');
      expect(deleteOf('shared/Talk.qslide'), findsNothing);
      expect(find.text('Rename'), findsOneWidget);
    });
  });
}
