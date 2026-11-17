import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/pages/file_browser_page.dart';
import 'package:quark/pages/generic_file_viewer_page.dart';
import 'package:quark/pages/pdf_viewer_page.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/pages/video_viewer_page.dart';
import 'package:quark/router.dart' as app;
import 'package:quark/router.dart' show AppRoutes;
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../support/fake_io_http.dart';
import '../support/fake_video_player_platform.dart';
import '../support/secure_storage.dart';

/// Records the paths every outgoing request is sent to, and answers each one
/// with enough of a Quark that nothing under test hangs waiting.
FakeIoQuark _recordingQuark() => FakeIoQuark((method, url) async {
  // A directory listing is the slow call in the real app — a folder with a
  // lot of files is exactly when the empty-state flash was visible — so hold
  // it open long enough for a test to pump inside the window. Recorded first,
  // so a test asserting the request was issued does not have to wait for it.
  if (url.path.endsWith('/api/v0/files')) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return (status: _statusFor(url), body: _bodyFor(url));
});

/// Extensions the fake stat reports as files. Every other path is a folder.
bool _statNamesAFile(String path) =>
    const ['.pdf', '.qslide', '.jpg', '.docx'].any(path.endsWith);

/// A path under `missing` does not exist: stat and listing both 404, as the
/// Quark answers for a deep link to a folder that is not there.
int _statusFor(Uri url) {
  final path =
      url.queryParameters['filePath'] ?? url.queryParameters['rootDir'] ?? '';
  return path.startsWith('missing') || path.startsWith('/missing') ? 404 : 200;
}

/// Enough of a backend for the deep-link flow to run for real: the page has
/// to reach the qsheet branch and push the editor itself.
String _bodyFor(Uri url) {
  if (url.path.endsWith('/api/v0/files/stat')) {
    final path = url.queryParameters['filePath'] ?? '';
    final isFile = _statNamesAFile(path);
    return jsonEncode({
      'isDir': !isFile,
      'fileType': isFile ? path.split('.').last : 'folder',
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
        'name': 'report.pdf',
        'size': 12,
        'isDir': false,
        'dirPath': '${url.queryParameters['rootDir'] ?? ''}/report.pdf',
        'fileType': 'pdf',
      },
      {
        'name': 'notes.docx',
        'size': 12,
        'isDir': false,
        'dirPath': '${url.queryParameters['rootDir'] ?? ''}/notes.docx',
        'fileType': 'docx',
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // The session token lives in secure storage on native platforms, and
    // there's no plugin behind it in a unit test.
    mockSecureStorage();
  });

  late FakeIoQuark overrides;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    await AppSettings.instance.addHost(
      HostEntry(name: 'Test', hostAddress: 'http://localhost:8080'),
    );
    overrides = _recordingQuark();
  });

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

  /// Pumps the browser at [location] under a router nested like
  /// lib/router.dart, with the app's real `/view` route beside it.
  Future<GoRouter> pumpRouted(WidgetTester tester, String location) async {
    final router = GoRouter(
      initialLocation: location,
      routes: [
        app.router.configuration.routes.whereType<GoRoute>().firstWhere(
          (route) => route.path == '${AppRoutes.viewFile}/:path(.*)',
        ),
        GoRoute(
          path: '${AppRoutes.slides}/:path(.*)',
          builder: (_, _) => const Text('slide editor'),
        ),
        GoRoute(
          path: '/files',
          builder: (_, _) => const FileBrowserPage(),
          routes: [
            GoRoute(
              path: ':path(.*)',
              builder: (_, state) => FileBrowserPage(
                initialPath: state.pathParameters['path'],
                deviceSerial: state.uri.queryParameters['serial'] ?? '',
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    return router;
  }

  testWidgets('a route pointing at a file opens it at its own URL', (
    tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      final router = await pumpRouted(tester, '/files/report.pdf');
      // Let the deep link resolve: stat names a file, and the browser hands
      // it to its viewer's URL (#2328).
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(router.state.uri.path, '/view/report.pdf');
      expect(find.byType(PdfViewerPage), findsOneWidget);
      expect(find.byType(FileBrowserPage), findsNothing);

      // AutoRefreshMixin's timer used to reissue the doomed listing every
      // interval while the browser sat under the viewer on the file's path.
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

  // The slide editor leaves for the Slides list unless told otherwise (#2896),
  // which is not where a deck opened from Files came from (#2403).
  testWidgets('a presentation opens saying which folder it came from', (
    tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      final router = await pumpRouted(tester, '/files/talks/deck.qslide');
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('slide editor'), findsOneWidget);
      expect(
        router.state.uri.toString(),
        '/slides/talks/deck.qslide?from=/files/talks',
      );
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('a drive link to a file does not reopen it on back', (
    tester,
  ) async {
    // #2328: `/files/<file>?serial=` was compared to the file URL without
    // the serial, so opening the viewer pushed a second history entry.
    // Closing replaced only that one, and browser back landed on the file
    // URL, which opened the viewer again.
    const link = '/files/papers/report.pdf?serial=STICK';
    final history = <String>[link];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.navigation, (call) async {
          if (call.method != 'routeInformationUpdated') return null;
          final args = call.arguments as Map;
          final uri = (args['uri'] ?? args['location']).toString();
          if (args['replace'] == true && history.isNotEmpty) {
            history.last = uri;
          } else {
            history.add(uri);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.navigation, null),
    );

    await HttpOverrides.runZoned(() async {
      final router = await pumpRouted(tester, link);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(PdfViewerPage), findsOneWidget);
      expect(
        router.state.uri.toString(),
        '/view/papers/report.pdf?serial=STICK',
      );

      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(router.state.uri.toString(), '/files/papers?serial=STICK');
      expect(find.byType(PdfViewerPage), findsNothing);
      // The file URL was replaced on the way to the viewer, so it is not
      // still sitting under the folder for back to land on.
      expect(history, ['/files/papers?serial=STICK']);
      // The folder listing's delay is still in flight; let it finish, then
      // unmount so nothing schedules another one.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('a folder route that does not exist ends in an error', (
    tester,
  ) async {
    // #2073: the stat 404s, and a path that does not look like a file was
    // handed to `_setPath` — which does nothing when the route already points
    // there, as a deep link's does. No listing was ever issued, so the page
    // sat on "Opening folder" forever with no way out but the browser's back.
    final overrides = _recordingQuark();
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
      await pumpRouted(tester, '/files/report.pdf');
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

  /// [pumpRouted] at [location], then taps [name] once it is listed.
  Future<GoRouter> clickFile(
    WidgetTester tester,
    String location,
    String name,
  ) async {
    final router = await pumpRouted(tester, location);
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
    // bytes.
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

  testWidgets('clicking a photo opens it at its own URL', (tester) async {
    await HttpOverrides.runZoned(() async {
      final router = await clickPhoto(tester, '/files/photos');
      expect(router.state.uri.path, '/view/photos/beach.jpg');
      // The viewer is the route. A second browser used to stack over it.
      expect(find.byType(FileBrowserPage), findsNothing);
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('clicking a photo in the home folder shows its URL', (
    tester,
  ) async {
    // #2002: /files/beach.jpg was a nested page under /files, and going to it
    // stacked a second browser over the viewer.
    await HttpOverrides.runZoned(() async {
      final router = await clickPhoto(tester, '/files');
      expect(router.state.uri.path, '/view/beach.jpg');
      expect(find.byType(FileBrowserPage), findsNothing);
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('clicking a pdf opens it at its own URL', (tester) async {
    // #2328: the viewer was pushed and never touched the URL, so it
    // could not be reloaded, shared or closed with browser back.
    await HttpOverrides.runZoned(() async {
      final router = await clickFile(tester, '/files/papers', 'report.pdf');
      await tester.pump(const Duration(seconds: 1));

      expect(router.state.uri.path, '/view/papers/report.pdf');
      expect(find.byType(PdfViewerPage), findsOneWidget);
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

    /// Unmounts the page so the player's timers, and a folder listing still
    /// in flight, do not outlive the test.
    Future<void> unmount(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
    }

    for (final folder in ['/files', '/files/movies']) {
      final clip = folder == '/files'
          ? '/view/clip.mp4'
          : '/view/${folder.substring(7)}/clip.mp4';

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
          await unmount(tester);
        }, createHttpClient: overrides.createHttpClient);
      });

      testWidgets('in $folder, closing it returns to the folder', (
        tester,
      ) async {
        await HttpOverrides.runZoned(() async {
          final router = await clickVideo(tester, folder);
          await tester.tap(find.byType(BackButton));
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

  // #2328: a photo and a generic file (no viewer of its own) each get a
  // history entry at `/view`, browser back and the close button return to
  // the folder, and pasting either URL opens that viewer.
  group('images and the generic viewer', () {
    final cases = <(String folder, String name, Type viewer)>[
      ('/files', 'beach.jpg', ImageViewerPage),
      ('/files/photos', 'beach.jpg', ImageViewerPage),
      ('/files', 'notes.docx', GenericFileViewerPage),
      ('/files/papers', 'notes.docx', GenericFileViewerPage),
    ];

    String viewPath(String folder, String name) => folder == '/files'
        ? '/view/$name'
        : '/view/${folder.substring('/files/'.length)}/$name';

    Future<void> unmount(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
    }

    /// What the router reports to the engine. [history] starts as the page
    /// already on screen; a `replace` overwrites the last entry.
    void watchHistory(List<String> history) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.navigation, (call) async {
            if (call.method != 'routeInformationUpdated') return null;
            final args = call.arguments as Map;
            final uri = (args['uri'] ?? args['location']).toString();
            if (args['replace'] == true && history.isNotEmpty) {
              history.last = uri;
            } else {
              history.add(uri);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.navigation, null),
      );
    }

    for (final (folder, name, viewer) in cases) {
      final opened = viewPath(folder, name);

      testWidgets('tapping $name from $folder opens $opened', (tester) async {
        // The folder stays under the viewer, so browser back can return to it.
        final history = <String>[folder];
        watchHistory(history);

        await HttpOverrides.runZoned(() async {
          final router = await clickFile(tester, folder, name);
          await tester.pump(const Duration(seconds: 1));

          expect(router.state.uri.path, opened);
          expect(find.byType(viewer), findsOneWidget);
          expect(find.byType(FileBrowserPage), findsNothing);
          expect(history, [folder, opened]);
          await unmount(tester);
        }, createHttpClient: overrides.createHttpClient);
      });

      testWidgets('browser back from $name in $folder returns there', (
        tester,
      ) async {
        await HttpOverrides.runZoned(() async {
          final router = await clickFile(tester, folder, name);
          await tester.pump(const Duration(seconds: 1));
          await router.routeInformationProvider.didPushRouteInformation(
            RouteInformation(uri: Uri.parse(folder)),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(router.state.uri.path, folder);
          expect(find.byType(viewer), findsNothing);
          expect(find.byType(FileBrowserPage), findsOneWidget);
          await unmount(tester);
        }, createHttpClient: overrides.createHttpClient);
      });

      testWidgets('closing $name in $folder returns there', (tester) async {
        // Seeded with the folder the tap pushes off of. Closing replaces the
        // viewer entry, so back from the folder does not reopen it.
        final history = <String>[folder];
        watchHistory(history);

        await HttpOverrides.runZoned(() async {
          final router = await clickFile(tester, folder, name);
          await tester.pump(const Duration(seconds: 1));
          expect(history, [folder, opened]);
          // Photos close from their own button. Every other viewer uses the
          // chrome back button.
          final close = viewer == ImageViewerPage
              ? find.byKey(const ValueKey('image_viewer_close'))
              : find.byType(BackButton);
          await tester.tap(close);
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(router.state.uri.path, folder);
          expect(find.byType(viewer), findsNothing);
          expect(find.byType(FileBrowserPage), findsOneWidget);
          expect(history, [folder, folder]);
          await unmount(tester);
        }, createHttpClient: overrides.createHttpClient);
      });
    }

    final links = <(String link, String opened, Type viewer)>[
      ('/files/beach.jpg', '/view/beach.jpg', ImageViewerPage),
      ('/files/photos/beach.jpg', '/view/photos/beach.jpg', ImageViewerPage),
      ('/files/notes.docx', '/view/notes.docx', GenericFileViewerPage),
      (
        '/files/papers/notes.docx',
        '/view/papers/notes.docx',
        GenericFileViewerPage,
      ),
      ('/view/photos/beach.jpg', '/view/photos/beach.jpg', ImageViewerPage),
      (
        '/view/papers/notes.docx',
        '/view/papers/notes.docx',
        GenericFileViewerPage,
      ),
    ];

    for (final (link, opened, viewer) in links) {
      testWidgets('opening $link shows $opened', (tester) async {
        await HttpOverrides.runZoned(() async {
          final router = await pumpRouted(tester, link);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(router.state.uri.path, opened);
          expect(find.byType(viewer), findsOneWidget);
          expect(find.byType(FileBrowserPage), findsNothing);
          await unmount(tester);
        }, createHttpClient: overrides.createHttpClient);
      });
    }
  });
}
