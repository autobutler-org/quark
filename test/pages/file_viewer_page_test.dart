import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/pages/audio_player_page.dart';
import 'package:quark/pages/file_viewer_page.dart';
import 'package:quark/pages/generic_file_viewer_page.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/pages/pdf_viewer_page.dart';
import 'package:quark/pages/svg_viewer_page.dart';
import 'package:quark/pages/video_viewer_page.dart';
import 'package:quark/router.dart';
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
  }) async {
    final view = router.configuration.routes.whereType<GoRoute>().firstWhere(
      (route) => route.path == '${AppRoutes.viewFile}/:path(.*)',
    );
    final r = GoRouter(
      initialLocation: AppRoutes.filesPath(folder),
      routes: [
        if (downloadBytes == null)
          view
        else
          GoRoute(
            path: view.path,
            redirect: view.redirect,
            builder: (_, state) => FileViewerPage(
              filePath: state.pathParameters['path']!,
              downloadBytes: downloadBytes,
            ),
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
    r.go(AppRoutes.viewFilePath(file));
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
}
