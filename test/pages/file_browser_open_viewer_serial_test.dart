import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/models/paginated_photos_response.dart' as wire;
import 'package:quark/models/photo_sort.dart';
import 'package:quark/pages/audio_player_page.dart';
import 'package:quark/pages/file_browser_page.dart';
import 'package:quark/pages/file_viewer_page.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/pages/pdf_viewer_page.dart';
import 'package:quark/pages/video_viewer_page.dart';
import 'package:quark/router.dart' as app;
import 'package:quark/router.dart' show AppRoutes;
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../support/fake_video_player_platform.dart';

/// #3337: tapping a file in Files opened its viewer on the first *selected*
/// device rather than the device the file is on, so every file on a second
/// drive opened a black viewer ("it's no longer there"). Each test lists two
/// devices — the built-in drive `A` and a stick with serial `B` — with every
/// file on `B`, taps one, and reads the serial the `/view` route and its
/// viewer were handed (#3350).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  Map<String, Object?> device(String name, {String serial = ''}) => {
    'name': name,
    'devicePath': '/dev/$name',
    'mountPoint': '/mnt/$name',
    'isInternal': serial.isEmpty,
    'isEnabled': true,
    if (serial.isNotEmpty) 'usbInfo': {'serial': serial},
  };

  Map<String, Object?> onB(String name, String fileType) => {
    'name': name,
    'size': 12,
    'isDir': false,
    'deviceName': 'B',
    'devicePath': '/dev/B',
    'deviceSerial': 'B',
    'dirPath': 'trip/$name',
    'fileType': fileType,
  };

  late List<Uri> requested;
  final realVideoPlatform = VideoPlayerPlatform.instance;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  setUp(() async {
    requested = [];
    VideoPlayerPlatform.instance = FakeVideoPlayerPlatform();
    // Before the host is set: the shared client is built once per host and
    // kept (#1782), so it has to come from this factory.
    sharedHttpClientFactory = () => MockClient((request) async {
      requested.add(request.url);
      final path = request.url.path;
      if (path.endsWith('/storage/devices/status')) {
        return http.Response(
          jsonEncode({
            'devices': [device('A'), device('B', serial: 'B')],
          }),
          200,
        );
      }
      // The merged listing every case shows, whatever the device filter:
      // with only A selected the stick's entries are still on screen.
      if (path.endsWith('/api/v0/files')) {
        return http.Response(
          jsonEncode([
            onB('photo.jpg', 'image'),
            onB('logo.svg', 'svg'),
            onB('clip.mp4', 'video'),
            onB('song.mp3', 'audio'),
            onB('report.pdf', 'pdf'),
            onB('bundle.zip', 'archive'),
          ]),
          200,
        );
      }
      return http.Response(path.endsWith('/health') ? '{}' : '[]', 200);
    });
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    await AppSettings.instance.addHost(
      HostEntry(name: 'Test', hostAddress: 'http://localhost:8080'),
    );
    StorageService.invalidateDeviceCache();
  });

  tearDown(() {
    VideoPlayerPlatform.instance = realVideoPlatform;
    StorageService.invalidateDeviceCache();
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  /// Pumps the browser at /files/trip beside the app's real `/view` route.
  Future<GoRouter> pumpRouted(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/files/trip',
      routes: [
        app.router.configuration.routes.whereType<GoRoute>().firstWhere(
          (route) => route.path == '${AppRoutes.viewFile}/:path(.*)',
        ),
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
    return router;
  }

  /// Taps the device chip for [name], toggling it out of (or into) the view.
  Future<void> toggleDevice(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(ValueKey('file_top_bar_device_/dev/$name')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  /// Whether the Quark was asked for [name] on device B.
  bool askedForOnB(String name) => requested.any(
    (u) =>
        u.queryParameters['serial'] == 'B' &&
        u.queryParameters.values.any((v) => v.endsWith(name)),
  );

  /// Each kind `_openResolvedFile` routes to `/view`, and how to read the
  /// serial its viewer ended up with.
  final kinds = <String, String? Function(WidgetTester)>{
    'photo.jpg': (t) =>
        t.widget<ImageViewerPage>(find.byType(ImageViewerPage)).serial,
    'logo.svg': (_) => askedForOnB('logo.svg') ? 'B' : null,
    'clip.mp4': (t) => t
        .widget<VideoViewerPage>(find.byType(VideoViewerPage))
        .url
        .queryParameters['serial'],
    'song.mp3': (t) => t
        .widget<AudioPlayerPage>(find.byType(AudioPlayerPage))
        .url
        .queryParameters['serial'],
    'report.pdf': (t) =>
        t.widget<PdfViewerPage>(find.byType(PdfViewerPage)).serial,
  };

  /// The device selection each case starts from, as chips to toggle off.
  const selections = <String, List<String>>{
    'every device selected': [],
    'only A selected': ['B'],
    'only B selected': ['A'],
  };

  for (final MapEntry(key: selection, value: deselect) in selections.entries) {
    group('with $selection', () {
      for (final MapEntry(key: name, value: viewerSerial) in kinds.entries) {
        testWidgets('$name opens on its own device', (tester) async {
          final router = await pumpRouted(tester);
          for (final device in deselect) {
            await toggleDevice(tester, device);
          }

          await tester.tap(find.text(name));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          await tester.pump();

          expect(router.state.uri.path, '/view/trip/$name');
          expect(router.state.uri.queryParameters['serial'], 'B');
          expect(
            tester.widget<FileViewerPage>(find.byType(FileViewerPage)).serial,
            'B',
          );
          expect(viewerSerial(tester), 'B');
          if (name == 'photo.jpg') {
            expect(askedForOnB(name), isTrue, reason: 'the photo is on B');
          }

          // The video player's timers and the folder listing must not
          // outlive the test.
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpWidget(const SizedBox());
        });
      }
    });
  }

  // An archive opens as a folder, listed from the drive it sits on rather
  // than the first one the view shows.
  testWidgets('an archive is listed from its own device', (tester) async {
    await pumpRouted(tester);

    await tester.tap(find.text('bundle.zip'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final listings = requested.where(
      (u) => u.path.endsWith('/api/v0/files/list-archive'),
    );
    expect(listings, isNotEmpty);
    expect(listings.map((u) => u.queryParameters['serial']), everyElement('B'));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox());
  });

  // The Photos tab already opens each photo on its own device; this keeps the
  // two from drifting apart.
  test('Photos opens a photo with that photo\'s own serial', () async {
    final downloads = <String?>[];
    final controller = PhotosController(
      isWeb: true,
      activeHost: () => 'http://localhost:8080',
      getPhotos:
          ({
            int offset = 0,
            int limit = 50,
            String? serial,
            PhotoSortField sort = PhotoSortField.added,
            PhotoSortOrder order = PhotoSortOrder.desc,
            String? q,
          }) async => wire.PaginatedPhotosResponse(
            photos: [
              wire.PhotoItem(
                relPath: 'trip/photo.jpg',
                fileName: 'photo.jpg',
                size: 1,
                mtime: 0,
                serial: 'B',
              ),
            ],
            total: 1,
            offset: offset,
            limit: limit,
          ),
      listFavoriteKeys: () async => {},
      listAlbums: ({bool tree = false}) async => [],
      downloadFileBytes: (path, {String? serial, String? fileName}) async {
        downloads.add(serial);
        return Uint8List.fromList([1]);
      },
    );
    await controller.refresh();

    final opened = await controller.openPhotoAt(0);

    expect(opened?.$4, 'B');
    expect(downloads, ['B']);
    controller.dispose();
  });
}
