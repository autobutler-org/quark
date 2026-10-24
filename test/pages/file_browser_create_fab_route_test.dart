import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/pages/file_browser_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/widgets/file_browser/file_browser_create_fab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_io_http.dart';
import '../support/secure_storage.dart';
import '../support/tap_target_guidelines.dart' show setViewport;

/// A folder of .qdoc files, for opening one the way a user does: by tapping
/// its row, or by loading its `/files` URL.
FakeIoQuark _listingQuark() =>
    FakeIoQuark((method, url) async => (status: 200, body: _bodyFor(url)));

String _bodyFor(Uri url) {
  if (url.path.endsWith('/api/v0/files/stat')) {
    final path = url.queryParameters['filePath'] ?? '';
    final isFile = path.endsWith('.qdoc');
    return jsonEncode({
      'isDir': !isFile,
      'fileType': isFile ? 'qdoc' : 'folder',
      'name': path.split('/').last,
    });
  }
  if (url.path.endsWith('/api/v0/files')) {
    return jsonEncode([
      for (var i = 0; i < 40; i++)
        {
          'name': 'doc$i.qdoc',
          'size': 12,
          'isDir': false,
          'dirPath': '/doc$i.qdoc',
          'fileType': 'qdoc',
        },
    ]);
  }
  return '[]';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(mockSecureStorage);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    await AppSettings.instance.addHost(
      HostEntry(name: 'Test', hostAddress: 'http://localhost:8080'),
    );
  });

  tearDown(resetSharedHttpClient);

  bool fabVisible(WidgetTester tester) => tester
      .widget<FileBrowserCreateFab>(find.byType(FileBrowserCreateFab))
      .visible;

  /// Both /files routes render FileBrowserPage, exactly as lib/router.dart
  /// does. The editor routes stand in for the real editors, which would
  /// download the file.
  GoRouter buildRouter(String initialLocation) => GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.files,
        builder: (_, _) => const FileBrowserPage(),
        routes: [
          GoRoute(
            path: ':path(.*)',
            builder: (_, state) =>
                FileBrowserPage(initialPath: state.pathParameters['path']),
          ),
        ],
      ),
      GoRoute(
        path: '${AppRoutes.docs}/:path(.*)',
        builder: (_, state) =>
            Text('doc editor ${state.pathParameters['path']}'),
      ),
    ],
  );

  String location(GoRouter router) =>
      router.routeInformationProvider.value.uri.toString();

  testWidgets('the create FAB comes back after a routed qdoc open', (
    tester,
  ) async {
    setViewport(tester, const Size(600, 900));

    await HttpOverrides.runZoned(() async {
      final router = buildRouter(AppRoutes.files);
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(fabVisible(tester), isTrue, reason: 'FAB starts visible');

      await tester.drag(find.text('doc0.qdoc'), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(fabVisible(tester), isFalse, reason: 'scrolling down hides it');

      await tester.tap(find.text('doc15.qdoc'));
      await tester.pumpAndSettle();
      expect(find.text('doc editor doc15.qdoc'), findsOneWidget);

      // Close the editor the way the app does: back to the containing folder.
      router.go(AppRoutes.files);
      await tester.pumpAndSettle();

      expect(fabVisible(tester), isTrue, reason: 'back on the list (#1811)');
    }, createHttpClient: _listingQuark().createHttpClient);
  });

  testWidgets('a doc opened from the home folder is at its own URL (#2078)', (
    tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      final router = buildRouter(AppRoutes.files);
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.text('doc1.qdoc'));
      await tester.pumpAndSettle();

      // A reload reads the address bar; /files would reopen the folder.
      expect(location(router), AppRoutes.docFile('doc1.qdoc'));
      expect(find.text('doc editor doc1.qdoc'), findsOneWidget);
    }, createHttpClient: _listingQuark().createHttpClient);
  });

  testWidgets('a /files deep link to a doc lands on the doc URL', (
    tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      final router = buildRouter(AppRoutes.filesPath('doc3.qdoc'));
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(location(router), AppRoutes.docFile('doc3.qdoc'));
      expect(find.text('doc editor doc3.qdoc'), findsOneWidget);
    }, createHttpClient: _listingQuark().createHttpClient);
  });
}
