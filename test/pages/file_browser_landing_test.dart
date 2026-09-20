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

/// Records where every request went and answers each one with an empty JSON
/// listing, so nothing under test hangs waiting for a Quark.
class _RecordingHttpOverrides extends HttpOverrides {
  final List<Uri> requested = [];

  /// What a stat answers with. A member may list `groups` but not stat it:
  /// their grant sits on the group's own folder, and stat asks for read on
  /// the path itself.
  int statStatus = 200;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _RecordingClient(requested, () => statStatus);
}

class _RecordingClient implements HttpClient {
  _RecordingClient(this.requested, this.statStatus);
  final List<Uri> requested;
  final int Function() statStatus;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    requested.add(url);
    final status = url.path.endsWith('/api/v0/files/stat') ? statStatus() : 200;
    return _RecordingRequest(url, _bodyFor(url), status);
  }

  static String _bodyFor(Uri url) {
    if (url.path.endsWith('/api/v0/files/stat')) {
      return jsonEncode({'isDir': true, 'fileType': 'folder', 'name': 'docs'});
    }
    return '[]';
  }

  // Everything else the client surface exposes is irrelevant here — swallow
  // it rather than throwing, so unrelated setup calls do not masquerade as
  // the behavior under test.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecordingRequest implements HttpClientRequest {
  _RecordingRequest(this.uri, this.body, this.status);
  @override
  final Uri uri;
  final String body;
  final int status;
  @override
  final HttpHeaders headers = _EmptyHeaders();

  @override
  Future<HttpClientResponse> close() async => _RecordingResponse(body, status);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<void> flush() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecordingResponse implements HttpClientResponse {
  _RecordingResponse(this.body, this.statusCode);
  final String body;

  @override
  final int statusCode;
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

/// #2139: a member's grants are sparse, so the real root holds nothing but the
/// `users` and `groups` scaffolding and their own files sit two clicks down.
/// The browser opens in their home instead — but only when the URL names no
/// path of its own.
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

  late _RecordingHttpOverrides overrides;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    await AppSettings.instance.addHost(
      HostEntry(name: 'Test', hostAddress: 'http://localhost:8080'),
    );
    await AppSettings.instance.setUsername('alice');
    AppSettings.instance.isAdmin.value = false;
    FileBrowserCache.instance.clearOpenFile();
    overrides = _RecordingHttpOverrides();
  });

  tearDown(() async {
    AppSettings.instance.isAdmin.value = false;
    await AppSettings.instance.setUsername(null);
    FileBrowserCache.instance.clearOpenFile();
  });

  // The shared client is built once and kept (#1782), so a client built inside
  // one test's HttpOverrides zone would answer the next test's requests too.
  tearDown(resetSharedHttpClient);

  /// Every listing request, as the `rootDir` each one asked for. A request
  /// with no `rootDir` is the real root, and reads as ''.
  List<String> listedPaths(List<Uri> all) => all
      .where((u) => u.path.endsWith('/api/v0/files'))
      .map((u) => u.queryParameters['rootDir'] ?? '')
      .toList();

  Future<void> pumpBrowser(WidgetTester tester, {String? initialPath}) async {
    await tester.pumpWidget(
      MaterialApp(home: FileBrowserPage(initialPath: initialPath)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('a member lands in their own files', (tester) async {
    await HttpOverrides.runZoned(() async {
      await pumpBrowser(tester);

      expect(
        listedPaths(overrides.requested),
        contains('users/alice'),
        reason: 'a bare /files opens the signed-in member\'s home',
      );
      expect(
        listedPaths(overrides.requested),
        isNot(contains('')),
        reason: 'the real root holds scaffolding, not their files',
      );
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('an admin lands at the real root', (tester) async {
    AppSettings.instance.isAdmin.value = true;

    await HttpOverrides.runZoned(() async {
      await pumpBrowser(tester);

      expect(listedPaths(overrides.requested), contains(''));
      expect(listedPaths(overrides.requested), isNot(contains('users/alice')));
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('a deep link wins over the landing path', (tester) async {
    await HttpOverrides.runZoned(() async {
      await pumpBrowser(tester, initialPath: '/users/bob/shared');

      expect(
        listedPaths(overrides.requested),
        contains('users/bob/shared'),
        reason: 'a path in the URL is what the user asked for',
      );
      expect(
        listedPaths(overrides.requested),
        isNot(contains('users/alice')),
        reason: 'the home default must not steal a deep link or a reload',
      );
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('a folder whose stat fails is still listed at once', (
    tester,
  ) async {
    // A member may list `groups` but not stat it, and the listing is held back
    // until the stat says what the path is. When the stat fails, the folder
    // has to be listed there and then — it used to wait for the refresh timer,
    // spinning for as long as fifteen seconds.
    overrides.statStatus = 404;

    await HttpOverrides.runZoned(() async {
      await pumpBrowser(tester, initialPath: '/groups');
      // The stat answers after the first frames: the listing it gates is
      // issued once it comes back, not on the refresh timer.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        listedPaths(overrides.requested),
        contains('groups'),
        reason: 'a failed stat must not leave the folder unlisted',
      );
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('an admin flag arriving late moves the admin off their home', (
    tester,
  ) async {
    // The flag is not persisted: `/auth/status` answers after the page is
    // already built, so a reload lands an admin in their home first.
    await HttpOverrides.runZoned(() async {
      await pumpBrowser(tester);
      expect(listedPaths(overrides.requested), contains('users/alice'));

      AppSettings.instance.isAdmin.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        listedPaths(overrides.requested),
        contains(''),
        reason: 'the admin belongs at the root they would have landed on',
      );
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('a member sees My files and Groups, an admin All files too', (
    tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await pumpBrowser(tester);

      expect(find.byKey(const ValueKey('file_shortcut_my_files')), findsOne);
      expect(find.byKey(const ValueKey('file_shortcut_groups')), findsOne);
      expect(
        find.byKey(const ValueKey('file_shortcut_all_files')),
        findsNothing,
        reason: 'only an admin can open the real root',
      );

      AppSettings.instance.isAdmin.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('file_shortcut_all_files')), findsOne);
    }, createHttpClient: overrides.createHttpClient);
  });
}
