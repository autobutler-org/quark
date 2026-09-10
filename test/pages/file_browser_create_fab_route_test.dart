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

/// A folder of .qdoc files. Tapping one is the exact path #1811 describes:
/// `.qdoc` is not a generic-viewer type, so the browser navigates by route
/// (`context.go`) rather than pushing, and `/files/:path` rebuilds the very
/// same [FileBrowserPage] State underneath the editor it then pushes.
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

  testWidgets('the create FAB comes back after a routed qdoc open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await HttpOverrides.runZoned(() async {
      // Both routes render FileBrowserPage, exactly as lib/router.dart does,
      // so the State survives the go and the bug has somewhere to live.
      final router = GoRouter(
        initialLocation: AppRoutes.files,
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
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final browserState = tester.state(find.byType(FileBrowserPage));
      expect(browserState.mounted, isTrue);
      expect(fabVisible(tester), isTrue, reason: 'FAB starts visible');

      await tester.drag(find.text('doc0.qdoc'), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(fabVisible(tester), isFalse, reason: 'scrolling down hides it');

      await tester.tap(find.text('doc15.qdoc'));
      await tester.pumpAndSettle();

      // The /files page has to still be alive underneath, or the FAB would
      // reset for free and this would prove nothing about #1811.
      expect(browserState.mounted, isTrue, reason: '/files stays alive');

      // Close the editor the way the app does: the editor pops itself and
      // then sends the router back to the containing folder.
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      expect(navigator.canPop(), isTrue, reason: 'an editor must be on top');
      navigator.pop();
      await tester.pumpAndSettle();
      router.go(AppRoutes.files);
      await tester.pumpAndSettle();

      expect(fabVisible(tester), isTrue, reason: 'back on the list (#1811)');
    }, createHttpClient: (c) => _QdocListingClient());
  });
}
