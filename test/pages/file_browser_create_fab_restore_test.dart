import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/file_browser_cache.dart';
import 'package:quark/pages/file_browser_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/widgets/file_browser/file_browser_create_fab.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers every call with just enough of a backend for the listing to render:
/// a folder of PDFs, which is a type with no in-app viewer, so tapping one
/// pushes the generic file viewer over the browser — the flow #1811 is about.
class _ListingClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _Request(url, _bodyFor(url));

  static String _bodyFor(Uri url) {
    if (url.path.endsWith('/api/v0/files/stat')) {
      final path = url.queryParameters['filePath'] ?? '';
      return jsonEncode({
        'isDir': false,
        'fileType': 'pdf',
        'name': path.split('/').last,
      });
    }
    if (url.path.endsWith('/api/v0/files')) {
      return jsonEncode([
        for (var i = 0; i < 40; i++)
          {
            'name': 'file$i.pdf',
            'size': 12,
            'isDir': false,
            'dirPath': '/file$i.pdf',
            'fileType': 'pdf',
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

  // The shared client is built once and kept (#1782), so a client built inside
  // one test's HttpOverrides zone would answer the next test's requests too.
  tearDown(resetSharedHttpClient);

  bool fabVisible(WidgetTester tester) => tester
      .widget<FileBrowserCreateFab>(find.byType(FileBrowserCreateFab))
      .visible;

  testWidgets('the create FAB comes back after a pushed viewer pops', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        const MaterialApp(home: FileBrowserPage(initialPath: '/')),
      );
      await tester.pumpAndSettle();

      expect(fabVisible(tester), isTrue, reason: 'FAB starts visible');

      // Scroll the listing down far enough to trip the hide threshold.
      await tester.drag(find.text('file0.pdf'), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(fabVisible(tester), isFalse, reason: 'scrolling down hides it');

      // Open a PDF — no in-app viewer, so the page pushes the generic viewer
      // over itself and its own State is never disposed.
      await tester.tap(find.text('file15.pdf'));
      await tester.pumpAndSettle();

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isTrue, reason: 'a viewer must be on top');
      navigator.pop();
      await tester.pumpAndSettle();

      expect(fabVisible(tester), isTrue, reason: 'back on the list (#1811)');
    }, createHttpClient: (c) => _ListingClient());
  });
}
