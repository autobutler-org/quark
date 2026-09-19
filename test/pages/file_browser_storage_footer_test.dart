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
import 'package:shared_preferences/shared_preferences.dart';

/// Serves an empty folder and a health reading that the test controls, so it
/// can change the disk usage between refreshes and hold a reading in flight.
class _HealthClient implements HttpClient {
  /// The health response each request gets, in order.
  final List<Future<String>> readings = [];
  var _served = 0;

  /// Every path requested, in order.
  final List<String> paths = [];

  static String reading(int usedGiB) => jsonEncode({
    'diskPercent': usedGiB,
    'diskUsedBytes': usedGiB << 30,
    'diskTotalBytes': 100 << 30,
  });

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    paths.add(url.path);
    if (url.path.endsWith('/api/v0/health')) {
      return _Request(url, readings[_served++]);
    }
    return _Request(url, Future.value('[]'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this.uri, this.body);
  @override
  final Uri uri;
  final Future<String> body;
  @override
  final HttpHeaders headers = _EmptyHeaders();

  @override
  Future<HttpClientResponse> close() async => _Response(await body);

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

// The storage footer used to fetch health once, when it was first built, so
// nothing the page did afterward ever changed it (#2151).
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

  testWidgets('the refresh button updates the storage footer', (tester) async {
    final client = _HealthClient();
    final second = Completer<String>();
    client.readings
      ..add(Future.value(_HealthClient.reading(10)))
      ..add(second.future);

    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(const MaterialApp(home: FileBrowserPage()));
      await tester.pumpAndSettle();
      expect(find.text('10.0 GB / 100.0 GB'), findsOneWidget);

      // AutoRefreshMixin drops a refresh within a wall-clock second of the
      // last one, so let real time pass before pressing the button.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)),
      );
      await tester.tap(find.byKey(const ValueKey('refresh_button')));
      await tester.pump();
      expect(
        find.text('10.0 GB / 100.0 GB'),
        findsOneWidget,
        reason: 'the last reading stays up while the refresh is in flight',
      );

      second.complete(_HealthClient.reading(25));
      await tester.pumpAndSettle();
      expect(find.text('25.0 GB / 100.0 GB'), findsOneWidget);
    }, createHttpClient: (_) => client);
  });

  // Health is far slower than the listing on a real Quark, and waiting on it
  // held up every refresh of the file list (#2189).
  testWidgets('a slow health reading does not hold up the file listing', (
    tester,
  ) async {
    final client = _HealthClient();
    final health = Completer<String>();
    client.readings.add(health.future);

    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(const MaterialApp(home: FileBrowserPage()));
      await tester.pump();
      await tester.pump();
      expect(client.paths, contains('/api/v0/files'));
      expect(find.text('10.0 GB / 100.0 GB'), findsNothing);

      health.complete(_HealthClient.reading(10));
      await tester.pumpAndSettle();
      expect(find.text('10.0 GB / 100.0 GB'), findsOneWidget);
    }, createHttpClient: (_) => client);
  });
}
