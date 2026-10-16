import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/pages/audio_player_page.dart';
import 'package:quark/pages/file_viewer_page.dart';
import 'package:quark/pages/generic_file_viewer_page.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/pages/pdf_viewer_page.dart';
import 'package:quark/pages/svg_viewer_page.dart';
import 'package:quark/pages/video_viewer_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/widgets/image_viewer/current_photo.dart';
import 'package:quark/widgets/image_viewer/metadata_sidebar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../support/fake_video_player_platform.dart';

const _svg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4">'
    '<rect width="4" height="4" fill="red"/></svg>';

void main() {
  /// The browser's history stack, built from what the router reports to the
  /// engine: on web each report is a pushState, or a replaceState when it
  /// says `replace`.
  final history = <String>[];

  setUp(() {
    history.clear();
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
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.navigation, null);
  });

  final realPlatform = VideoPlayerPlatform.instance;
  setUp(() => VideoPlayerPlatform.instance = FakeVideoPlayerPlatform());
  tearDown(() => VideoPlayerPlatform.instance = realPlatform);

  /// The app's real `/view` route over a stand-in Files, opened the way the
  /// file browser opens it: `/files/<folder>` first, then `go` to the file.
  Future<GoRouter> openFromFolder(
    WidgetTester tester,
    String folder,
    String file, {
    Future<Uint8List?> Function(String, {String? serial})? downloadBytes,
    Future<List<FileNode>> Function(String, {List<String>? serials})? listFiles,
    String? from,
    String? serial,
  }) async {
    final view = router.configuration.routes.whereType<GoRoute>().firstWhere(
      (route) => route.path == '${AppRoutes.viewFile}/:path(.*)',
    );
    final r = GoRouter(
      initialLocation: AppRoutes.filesPath(folder),
      routes: [
        if (downloadBytes == null && listFiles == null)
          view
        else
          GoRoute(
            path: view.path,
            redirect: view.redirect,
            builder: (_, state) => FileViewerPage(
              filePath: state.pathParameters['path']!,
              serial: state.uri.queryParameters['serial'] ?? '',
              downloadBytes: downloadBytes ?? FilesService.downloadFileBytes,
              listFiles: listFiles ?? FilesService.getFiles,
            ),
          ),
        GoRoute(
          path: AppRoutes.books,
          builder: (_, _) => const Scaffold(body: Text('books')),
        ),
        GoRoute(
          path: AppRoutes.files,
          builder: (_, _) => const Scaffold(body: Text('files')),
          routes: [
            GoRoute(
              path: ':path(.*)',
              builder: (_, state) => const Scaffold(body: Text('folder')),
            ),
          ],
        ),
      ],
    );
    addTearDown(r.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pump();
    r.go(AppRoutes.viewFilePath(file, from: from, serial: serial));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    return r;
  }

  String at(GoRouter r) => r.routerDelegate.currentConfiguration.uri.toString();

  /// Unmounts the viewer so a player's or loader's timers end with the test.
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  testWidgets('a pdf opens the pdf viewer at its own URL', (tester) async {
    final r = await openFromFolder(tester, 'papers', 'papers/my report.pdf');

    expect(at(r), '/view/papers/my%20report.pdf');
    expect(history.last, '/view/papers/my%20report.pdf');
    // #1184: it used to land on the generic page, which only downloads.
    expect(find.byType(GenericFileViewerPage), findsNothing);
    final viewer = tester.widget<PdfViewerPage>(find.byType(PdfViewerPage));
    expect(viewer.filePath, 'papers/my report.pdf');
    expect(viewer.name, 'my report.pdf');
    await unmount(tester);
  });

  testWidgets('a type with no viewer opens the generic one', (tester) async {
    final r = await openFromFolder(tester, 'papers', 'papers/my report.docx');

    expect(at(r), '/view/papers/my%20report.docx');
    expect(find.byType(GenericFileViewerPage), findsOneWidget);
    expect(find.text('my report.docx'), findsWidgets);
  });

  testWidgets('closing replaces the viewer with its folder', (tester) async {
    final r = await openFromFolder(tester, 'papers', 'papers/report.pdf');
    expect(history, ['/files/papers', '/view/papers/report.pdf']);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(at(r), '/files/papers');
    expect(find.byType(PdfViewerPage), findsNothing);
    // Back from here must not bounce into the viewer again.
    expect(history, ['/files/papers', '/files/papers']);
  });

  // #1678: a book opened from Books used to close into its folder in Files.
  testWidgets('closing returns to the page the viewer was opened from', (
    tester,
  ) async {
    final r = await openFromFolder(
      tester,
      'papers',
      'papers/report.pdf',
      from: AppRoutes.books,
    );
    expect(at(r), '/view/papers/report.pdf?from=/books');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(at(r), AppRoutes.books);
    expect(find.text('books'), findsOneWidget);
  });

  testWidgets('a made-up origin still closes into the folder', (tester) async {
    final r = await openFromFolder(
      tester,
      'papers',
      'papers/report.pdf',
      from: 'https://example.com/books',
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(at(r), '/files/papers');
  });

  testWidgets('a system back closes it to the folder', (tester) async {
    final r = await openFromFolder(tester, 'photos', 'photos/beach.jpg');
    expect(find.byType(ImageViewerPage), findsOneWidget);

    // Both this page's scope and the photo viewer's own hear it; one close.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(at(r), '/files/photos');
    expect(history, ['/files/photos', '/files/photos']);
    await unmount(tester);
  });

  testWidgets('a photo opens the photo viewer on the Quark path', (
    tester,
  ) async {
    await openFromFolder(tester, 'photos', 'photos/beach.jpg');

    final viewer = tester.widget<ImageViewerPage>(find.byType(ImageViewerPage));
    expect(viewer.relPath, 'photos/beach.jpg');
    expect(viewer.name, 'beach.jpg');
    await unmount(tester);
  });

  testWidgets('a video and an audio file open their players', (tester) async {
    await openFromFolder(tester, 'movies', 'movies/clip.mp4');
    expect(find.byType(VideoViewerPage), findsOneWidget);
    await unmount(tester);

    await openFromFolder(tester, 'music', 'music/song.mp3');
    expect(find.byType(AudioPlayerPage), findsOneWidget);
    expect(find.byType(VideoViewerPage), findsNothing);
    await unmount(tester);
  });

  testWidgets('an svg is fetched and drawn', (tester) async {
    String? asked;
    await openFromFolder(
      tester,
      'art',
      'art/logo.svg',
      downloadBytes: (path, {serial}) async {
        asked = path;
        return Uint8List.fromList(utf8.encode(_svg));
      },
    );

    expect(asked, 'art/logo.svg');
    expect(find.byType(SvgViewerPage), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('an svg that will not download says so', (tester) async {
    await openFromFolder(
      tester,
      'art',
      'art/logo.svg',
      downloadBytes: (_, {serial}) async => null,
    );

    expect(find.byType(SvgPicture), findsNothing);
    expect(find.text("Couldn't open the file."), findsOneWidget);
  });

  // #3378, #3379: a photo opened from Files had nowhere to step, and then
  // waited on the folder's listing before it would show.
  group('a photo steps through its folder', () {
    // 64x64 solid PNG — the viewer needs bytes it can actually decode.
    final png = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAT0lEQVR42u3P'
        'QQkAAAgEsIttCIMZywi+hcEKLNXzWgQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE'
        'BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQELgvWNcGlSbHPawAAAABJRU5ErkJg'
        'gg==',
      ),
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      resetSharedHttpClient();
      // The viewer's own download of the opened photo, and its metadata.
      sharedHttpClientFactory = () => MockClient((request) async {
        if (request.url.path == '/api/v0/photos/metadata') {
          return http.Response('{}', 404);
        }
        return http.Response.bytes(png, 200);
      });
    });

    tearDown(() {
      resetSharedHttpClient();
      sharedHttpClientFactory = buildLocalTrustHttpClient;
    });

    FileNode node(String name, {bool isDir = false, String serial = ''}) =>
        FileNode(
          name: name,
          size: 1,
          isDir: isDir,
          deviceName: '',
          devicePath: '',
          deviceSerial: serial,
          dirPath: 'photos/$name',
        );

    /// Lets a photo decode, which takes real async, then settles.
    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      });
      await tester.pumpAndSettle();
    }

    ImageViewerPage viewer(WidgetTester tester) =>
        tester.widget<ImageViewerPage>(find.byType(ImageViewerPage));

    /// The name of the photo on screen, as the info sidebar has it.
    String shown(WidgetTester tester) =>
        tester.widget<MetadataSidebar>(find.byType(MetadataSidebar)).name;

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await settle(tester);
    }

    testWidgets('by name, skipping what is not a photo', (tester) async {
      final downloads = <String>[];
      List<String>? listedSerials;
      final r = await openFromFolder(
        tester,
        'photos',
        'photos/b.jpg',
        listFiles: (path, {serials}) async {
          expect(path, 'photos');
          listedSerials = serials;
          return [
            node('d.jpg'),
            node('c.txt'),
            node('e.jpg', isDir: true),
            node('A.jpg'),
            node('b.jpg'),
          ];
        },
        downloadBytes: (path, {serial}) async {
          downloads.add(path);
          return png;
        },
      );
      await settle(tester);
      expect(listedSerials, isNull);
      expect(viewer(tester).imageCount, 3);
      expect(viewer(tester).initialIndex, 1);
      expect(find.text('2 / 3'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(find.text('3 / 3'), findsOneWidget);
      expect(shown(tester), 'd.jpg');
      expect(downloads, contains('photos/d.jpg'));
      // The step replaced the viewer's entry; it did not add one.
      expect(history, ['/files/photos', '/view/photos/d.jpg']);

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(find.text('2 / 3'), findsOneWidget);
      expect(shown(tester), 'b.jpg');

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(find.text('1 / 3'), findsOneWidget);
      expect(shown(tester), 'A.jpg');
      expect(history, ['/files/photos', '/view/photos/A.jpg']);

      // Closing still lands on the folder, in the viewer's one entry.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(at(r), '/files/photos');
      expect(history, ['/files/photos', '/files/photos']);
    });

    testWidgets('on the folder\'s drive only', (tester) async {
      final downloads = <(String, String?)>[];
      List<String>? listedSerials;
      await openFromFolder(
        tester,
        'photos',
        'photos/b.jpg',
        serial: 'usb1',
        listFiles: (path, {serials}) async {
          listedSerials = serials;
          return [
            node('a.jpg', serial: 'usb1'),
            node('b.jpg', serial: 'usb1'),
            node('c.jpg'),
          ];
        },
        downloadBytes: (path, {serial}) async {
          downloads.add((path, serial));
          return png;
        },
      );
      await settle(tester);
      expect(listedSerials, ['usb1']);
      expect(viewer(tester).imageCount, 2);

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(shown(tester), 'a.jpg');
      expect(downloads, contains(('photos/a.jpg', 'usb1')));
      expect(history.last, '/view/photos/a.jpg?serial=usb1');
    });

    testWidgets('the photo shows before the listing lands', (tester) async {
      final listing = Completer<List<FileNode>>();
      await openFromFolder(
        tester,
        'photos',
        'photos/b.jpg',
        listFiles: (_, {serials}) => listing.future,
        downloadBytes: (_, {serial}) async => png,
      );
      await settle(tester);
      expect(find.byType(CurrentPhoto), findsOneWidget);
      expect(viewer(tester).imageCount, 1);

      listing.complete([node('a.jpg'), node('b.jpg'), node('c.jpg')]);
      await settle(tester);
      expect(find.byType(CurrentPhoto), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
      expect(shown(tester), 'b.jpg');
    });

    testWidgets('a listing that fails leaves the one photo', (tester) async {
      await openFromFolder(
        tester,
        'photos',
        'photos/b.jpg',
        listFiles: (_, {serials}) async => throw Exception('offline'),
        downloadBytes: (_, {serial}) async => png,
      );
      await settle(tester);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(find.byType(CurrentPhoto), findsOneWidget);
      expect(viewer(tester).imageCount, 1);
      expect(shown(tester), 'b.jpg');
      expect(history, ['/files/photos', '/view/photos/b.jpg']);
    });
  });
}
