import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/file_browser_cache.dart';
import 'package:quark/pages/file_browser_page.dart';
import 'package:quark/pages/audio_player_page.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/pages/video_viewer_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../support/fake_video_player_platform.dart';

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
    return _RecordingRequest(url, _bodyFor(url), _statusFor(url));
  }

  /// A path under `missing` does not exist: stat and listing both 404, as the
  /// Quark answers for a deep link to a folder that is not there.
  static int _statusFor(Uri url) {
    final path =
        url.queryParameters['filePath'] ?? url.queryParameters['rootDir'] ?? '';
    return path.startsWith('missing') || path.startsWith('/missing')
        ? 404
        : 200;
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
        {
          'name': 'beach.jpg',
          'size': 12,
          'isDir': false,
          'dirPath': '${url.queryParameters['rootDir'] ?? ''}/beach.jpg',
          'fileType': 'image',
        },
        {
          'name': 'song.mp3',
          'size': 12,
          'isDir': false,
          'dirPath': '${url.queryParameters['rootDir'] ?? ''}/song.mp3',
          'fileType': 'audio',
        },
        {
          'name': 'clip.mp4',
          'size': 12,
          'isDir': false,
          'dirPath': '${url.queryParameters['rootDir'] ?? ''}/clip.mp4',
          'fileType': 'video',
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

  // Everything else the client surface exposes is irrelevant here — swallow
  // it rather than throwing, so unrelated setup calls (connectionTimeout=,
  // close(force:)) do not masquerade as the behavior under test.
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

  testWidgets('a folder route that does not exist ends in an error', (
    tester,
  ) async {
    // #2073: the stat 404s, and a path that does not look like a file was
    // handed to `_setPath` — which does nothing when the route already points
    // there, as a deep link's does. No listing was ever issued, so the page
    // sat on "Opening folder" forever with no way out but the browser's back.
    final overrides = _RecordingHttpOverrides();
    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        const MaterialApp(home: FileBrowserPage(initialPath: 'missing')),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(listingsOf(overrides.requested, 'missing'), isNotEmpty);
      expect(find.text('Opening folder'), findsNothing);
      expect(find.text('Go to /files'), findsOneWidget);
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
      // The folder around the file is listed while it resolves (#1564).
      await tester.pump(const Duration(milliseconds: 300));
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

  /// Pumps the browser at [location] under a router nested like
  /// lib/router.dart, taps [name], and returns the router once the push
  /// animation — and the URL sync that follows it — is over.
  Future<GoRouter> clickFile(
    WidgetTester tester,
    String location,
    String name,
  ) async {
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/files',
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
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text(name));
    await tester.pump();
    return router;
  }

  /// [clickFile] on beach.jpg, checking the photo viewer lands without a stat.
  Future<GoRouter> clickPhoto(WidgetTester tester, String location) async {
    final router = await clickFile(tester, location, 'beach.jpg');
    // #1564: a click routed to the photo's URL, stat-ed it and downloaded it
    // whole before the viewer appeared. The listing already knows the type, so
    // the viewer is built within a frame of the tap (offstage only while the
    // route sets up its hero flight) and it is the viewer that asks for the
    // bytes. From the home folder that one frame builds the file's own page,
    // which the viewer lands on (#2002).
    await tester.pump();
    expect(find.byType(ImageViewerPage, skipOffstage: false), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(
      overrides.requested.where(
        (u) =>
            u.path.endsWith('/files/stat') &&
            (u.queryParameters['filePath'] ?? '').endsWith('beach.jpg'),
      ),
      isEmpty,
      reason: 'the listing already said this is an image',
    );
    expect(find.byType(ImageViewerPage), findsOneWidget);
    return router;
  }

  testWidgets('clicking a photo opens its viewer, then its URL follows', (
    tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      final router = await clickPhoto(tester, '/files/photos');
      expect(router.state.uri.path, '/files/photos/beach.jpg');
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('clicking a photo in the home folder shows its URL', (
    tester,
  ) async {
    // /files/beach.jpg is a nested page under /files. Going to it used to
    // stack a second browser over the viewer, so the URL stayed on /files.
    await HttpOverrides.runZoned(() async {
      final router = await clickPhoto(tester, '/files');
      expect(router.state.uri.path, '/files/beach.jpg');
    }, createHttpClient: overrides.createHttpClient);
  });

  group('clicking a video', () {
    final realPlatform = VideoPlayerPlatform.instance;
    setUp(() => VideoPlayerPlatform.instance = FakeVideoPlayerPlatform());
    tearDown(() => VideoPlayerPlatform.instance = realPlatform);

    /// [clickFile] on clip.mp4 in [folder], once its viewer is up.
    Future<GoRouter> clickVideo(WidgetTester tester, String folder) async {
      final router = await clickFile(tester, folder, 'clip.mp4');
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      return router;
    }

    /// Unmounts the viewer so the player's timers do not outlive the test.
    Future<void> unmount(WidgetTester tester) =>
        tester.pumpWidget(const SizedBox());

    for (final folder in ['/files', '/files/movies']) {
      final clip = folder == '/files' ? '/files/clip.mp4' : '$folder/clip.mp4';

      testWidgets('in $folder shows the video at $clip', (tester) async {
        // #2002: from the home folder the URL stayed on /files.
        await HttpOverrides.runZoned(() async {
          final router = await clickVideo(tester, folder);
          expect(router.state.uri.path, clip);
          expect(find.byType(VideoViewerPage), findsOneWidget);
          await unmount(tester);
        }, createHttpClient: overrides.createHttpClient);
      });

      testWidgets('in $folder, browser back closes it', (tester) async {
        await HttpOverrides.runZoned(() async {
          final router = await clickVideo(tester, folder);
          // What the engine hands the router when the browser goes back.
          await router.routeInformationProvider.didPushRouteInformation(
            RouteInformation(uri: Uri.parse(folder)),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(router.state.uri.path, folder);
          expect(find.byType(VideoViewerPage), findsNothing);
          expect(find.byType(FileBrowserPage), findsOneWidget);
          expect(
            FileBrowserCache.instance.isFileOpen(clip.substring(7)),
            isFalse,
          );
          await unmount(tester);
        }, createHttpClient: overrides.createHttpClient);
      });

      testWidgets('in $folder, closing it returns to the folder', (
        tester,
      ) async {
        await HttpOverrides.runZoned(() async {
          final router = await clickVideo(tester, folder);
          Navigator.of(tester.element(find.byType(VideoViewerPage))).pop();
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(router.state.uri.path, folder);
          expect(find.byType(VideoViewerPage), findsNothing);
          expect(find.byType(FileBrowserPage), findsOneWidget);
          await unmount(tester);
        }, createHttpClient: overrides.createHttpClient);
      });
    }
  });

  testWidgets('clicking an audio file opens the audio player', (tester) async {
    // #1573: audio shared the video case and opened VideoViewerPage, which has
    // no track to paint and showed only its black backdrop.
    await HttpOverrides.runZoned(() async {
      await clickFile(tester, '/files/music', 'song.mp3');
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(AudioPlayerPage), findsOneWidget);
      expect(find.byType(VideoViewerPage), findsNothing);
    }, createHttpClient: overrides.createHttpClient);
  });
}
