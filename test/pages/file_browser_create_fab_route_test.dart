import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/file_browser_cache.dart';
import 'package:quark/pages/file_browser_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/widgets/file_browser/file_browser_create_fab.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A folder of .qdoc files, for opening one the way a user does: by tapping
/// its row, or by loading its `/files` URL.
class _QdocListingClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _Request(url, _bodyFor(url));

  static String _bodyFor(Uri url) {
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

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this.uri, this.body);
  @override
  final Uri uri;
  final String body;
  @override
  final HttpHeaders headers = _EmptyHeaders();

  @override
  Future<HttpClientResponse> close() async => _Response(body);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<void> flush() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response implements HttpClientResponse {
  _Response(this.body);
  final String body;

  @override
  int get statusCode => 200;
  @override
  int get contentLength => -1;
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => false;
  @override
  String get reasonPhrase => 'OK';
  @override
  List<Cookie> get cookies => const [];
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  final HttpHeaders headers = _EmptyHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.fromIterable([utf8.encode(body)]).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _EmptyHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    await AppSettings.instance.addHost(
      HostEntry(name: 'Test', hostAddress: 'http://localhost:8080'),
    );
    FileBrowserCache.instance.clearOpenFile();
  });

  tearDown(FileBrowserCache.instance.clearOpenFile);
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
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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
    }, createHttpClient: (c) => _QdocListingClient());
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
    }, createHttpClient: (c) => _QdocListingClient());
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
    }, createHttpClient: (c) => _QdocListingClient());
  });
}
