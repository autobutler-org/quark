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

/// Records the paths every outgoing request is sent to, and answers each one
/// with an empty JSON listing so nothing under test hangs waiting.
class _RecordingHttpOverrides extends HttpOverrides {
  final List<Uri> requested = [];

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _RecordingClient(requested);
}

class _RecordingClient implements HttpClient {
  _RecordingClient(this.requested);
  final List<Uri> requested;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    requested.add(url);
    // A directory listing is the slow call in the real app — a folder with a
    // lot of files is exactly when the empty-state flash was visible — so hold
    // it open long enough for a test to pump inside the window. Recorded first,
    // so a test asserting the request was issued does not have to wait for it.
    if (url.path.endsWith('/api/v0/files')) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return _RecordingRequest(url, _bodyFor(url));
  }

  /// Enough of a backend for the deep-link flow to run for real: the page has
  /// to reach the qsheet branch and push the editor itself, because that is
  /// what marks the file open. Marking it open from the test instead trips the
  /// `isFileOpen` early return, which resets the path to the parent and hides
  /// the very request under test.
  static String _bodyFor(Uri url) {
    if (url.path.endsWith('/api/v0/files/stat')) {
      final path = url.queryParameters['filePath'] ?? '';
      final isFile = path.endsWith('.pdf');
      return jsonEncode({
        'isDir': !isFile,
        'fileType': isFile ? 'pdf' : 'folder',
        'name': path.split('/').last,
      });
    }
    if (url.path.endsWith('/api/v0/files')) {
      return jsonEncode([
        {
          'name': 'notes.txt',
          'size': 12,
          'isDir': false,
          'dirPath': '${url.queryParameters['rootDir'] ?? ''}/notes.txt',
          'fileType': 'txt',
        },
      ]);
    }
    return '[]';
  }

  // Everything else the client surface exposes is irrelevant here — swallow
  // it rather than throwing, so unrelated setup calls (connectionTimeout=,
  // close(force:)) do not masquerade as the behavior under test.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecordingRequest implements HttpClientRequest {
  _RecordingRequest(this.uri, this.body);
  @override
  final Uri uri;
  final String body;
  @override
  final HttpHeaders headers = _EmptyHeaders();

  @override
  Future<HttpClientResponse> close() async => _RecordingResponse(body);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<void> flush() async {}

  // Everything else the client surface exposes is irrelevant here — swallow
  // it rather than throwing, so unrelated setup calls (connectionTimeout=,
  // close(force:)) do not masquerade as the behavior under test.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecordingResponse implements HttpClientResponse {
  _RecordingResponse(this.body);
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

  // Everything else the client surface exposes is irrelevant here — swallow
  // it rather than throwing, so unrelated setup calls (connectionTimeout=,
  // close(force:)) do not masquerade as the behavior under test.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _EmptyHeaders implements HttpHeaders {
  // Everything else the client surface exposes is irrelevant here — swallow
  // it rather than throwing, so unrelated setup calls (connectionTimeout=,
  // close(force:)) do not masquerade as the behavior under test.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() {
    // The session token lives in secure storage on native platforms, and
    // there's no plugin behind it in a unit test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  late _RecordingHttpOverrides overrides;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    await AppSettings.instance.addHost(
      HostEntry(name: 'Test', hostAddress: 'http://localhost:8080'),
    );
    FileBrowserCache.instance.clearOpenFile();
    overrides = _RecordingHttpOverrides();
  });

  tearDown(FileBrowserCache.instance.clearOpenFile);

  // The shared client is built once and kept (#1782), so a client built inside
  // one test's HttpOverrides zone would answer the next test's requests too.
  tearDown(resetSharedHttpClient);

  /// Listing requests whose rootDir names [path] — the exact shape of the
  /// doomed request, so an unrelated root listing cannot pass or fail this.
  List<Uri> listingsOf(List<Uri> all, String path) => all
      .where(
        (u) =>
            u.path.endsWith('/api/v0/files') &&
            u.queryParameters['rootDir'] == path,
      )
      .toList();

  testWidgets('a route pointing at an open file is never listed', (
    tester,
  ) async {
    const filePath = '/report.pdf';

    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        const MaterialApp(home: FileBrowserPage(initialPath: filePath)),
      );
      // Let the deep link resolve: stat names a file, and the page marks it
      // open and pushes its viewer over itself. Any viewer reaches the same
      // state the bug needs — the browser mounted underneath with
      // `_currentPath` still on the file — so this uses the one that does not
      // also need a GoRouter in the tree.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        FileBrowserCache.instance.isFileOpen(filePath),
        isTrue,
        reason: 'the viewer must actually be open for this to test anything',
      );

      // The browser stays mounted underneath with `_currentPath` still on the
      // file, and AutoRefreshMixin's timer used to reissue the doomed listing
      // every interval for the whole session in the sheet.
      await tester.pump(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 60));

      expect(
        listingsOf(overrides.requested, 'report.pdf'),
        isEmpty,
        reason:
            'GET /api/v0/files?rootDir=report.pdf can only 404 — the path '
            'names a file, not a directory',
      );
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('a route resolving to a file never flashes the empty state', (
    tester,
  ) async {
    // #1808: `_reloadFiles` leaves `_filesFuture` on its pre-resolved empty
    // default for a file route, and AutoRefreshMixin's first refresh clears
    // `isInitialLoad` before `statFile` has answered — so the browser rendered
    // "No files yet" until the viewer took over.
    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        const MaterialApp(home: FileBrowserPage(initialPath: '/report.pdf')),
      );
      for (var i = 0; i < 8; i++) {
        expect(
          find.text('No files yet'),
          findsNothing,
          reason: 'the deep link names a file, not an empty folder',
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('a folder route never flashes the empty state before its list', (
    tester,
  ) async {
    // #1808: a deep link is a pending open until `statFile` says what it is,
    // so the first refresh issues no listing and leaves `_filesFuture` on its
    // pre-resolved empty default. Once stat answers "folder" and the real
    // listing is issued, `FutureBuilder` carries that empty result forward as
    // the new future's snapshot data — and with `isInitialLoad` already
    // cleared, "No files yet" rendered until the listing landed.
    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        const MaterialApp(home: FileBrowserPage(initialPath: '/Documents')),
      );
      for (var i = 0; i < 40; i++) {
        expect(
          find.text('No files yet'),
          findsNothing,
          reason: '/Documents has files — the listing was just still in flight',
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.text('notes.txt'), findsOneWidget);
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('a folder route is still listed', (tester) async {
    // The other half: the guard reads exact open-file state, never the name,
    // so a directory keeps loading normally.
    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        const MaterialApp(home: FileBrowserPage(initialPath: '/Documents')),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(listingsOf(overrides.requested, 'Documents'), isNotEmpty);
    }, createHttpClient: overrides.createHttpClient);
  });
}
