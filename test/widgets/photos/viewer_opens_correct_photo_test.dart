import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/controllers/albums_cache.dart';
import 'package:quark/controllers/photo_bytes_cache.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/controllers/photos_list_cache.dart';
import 'package:quark/models/paginated_photos_response.dart' as wire;
import 'package:quark/models/photo_album.dart';
import 'package:quark/models/photo_sort.dart';
import 'package:quark/pages/file_browser_page.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/router.dart' as app;
import 'package:quark/router.dart' show AppRoutes;
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/demo_photos_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/image_viewer/current_photo.dart';
import 'package:quark/widgets/photos/photos_search_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #3486: one acceptance matrix for "tapping a photo opens that photo", from
/// every place the viewer opens: the Photos grid, a Photos search result, an
/// album, Files, and a `/view` deep link (#2328).
///
/// Two devices, the built-in drive `A` and a stick `B`, each hold a
/// `trip/photo.jpg` with different pixels, and A is the first device, so a
/// viewer that falls back to it (#3337) shows the wrong picture. Every photo
/// the viewer can reach is its own PNG, and the photo on screen is read by its
/// hash. The library holds 364 photos with one page of 50 loaded, so a
/// counter that reads the loaded page (#3357) shows "/ 50".
///
/// Swipe, double-tap zoom and pinch are the viewer's own and do not depend on
/// where it was opened: `image_viewer_gestures_test` covers them. Videos do
/// not appear in Photos yet (#3428). Photo search asks the photos list, which
/// returns images only, so a video that shares the name never reaches the grid.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  /// Each photo the viewer can land on, as `serial:path`, with its color.
  const colors = <String, Color>{
    'A:trip/photo.jpg': Color(0xFFFF0000),
    'B:trip/photo.jpg': Color(0xFF0000FF),
    'A:camera/2.jpg': Color(0xFF00FF00),
    'B:trip/photo_old.jpg': Color(0xFFFFFF00),
    'A:trip/sunset.jpg': Color(0xFFFF00FF),
    'B:trip/a.jpg': Color(0xFF00FFFF),
    'B:trip/z.jpg': Color(0xFF808000),
  };

  /// The PNG of each photo in [colors], painted once; every other photo is
  /// [filler].
  final pictures = <String, Uint8List>{};
  late Uint8List filler;

  Future<Uint8List> paint(Color color) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(color, BlendMode.src);
    final image = await recorder.endRecording().toImage(64, 64);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  Future<void> paintPhotos(WidgetTester tester) async {
    if (pictures.isNotEmpty) return;
    await tester.runAsync(() async {
      for (final MapEntry(:key, :value) in colors.entries) {
        pictures[key] = await paint(value);
      }
      filler = await paint(const Color(0xFF808080));
    });
  }

  String hash(Uint8List bytes) => sha256.convert(bytes).toString();

  /// Every photo the Quark was asked for, as `serial:path`, in order.
  late List<String> downloads;

  /// Photos whose download answers 500 until taken out again.
  late Set<String> failing;

  /// The body of every favorite toggle.
  late List<Map<String, Object?>> favorites;

  /// The two-device Quark's disk: the photo at [path] on [serial].
  Uint8List read(String? serial, String path) {
    final key = '${serial ?? ''}:$path';
    downloads.add(key);
    if (failing.contains(key)) throw const ApiException(500);
    return pictures[key] ?? filler;
  }

  Map<String, Object?> device(String name, {String serial = ''}) => {
    'name': name,
    'devicePath': '/dev/$name',
    'mountPoint': '/mnt/$name',
    'isInternal': serial.isEmpty,
    'isEnabled': true,
    if (serial.isNotEmpty) 'usbInfo': {'serial': serial},
  };

  Map<String, Object?> onB(String name) => {
    'name': name,
    'size': 12,
    'isDir': false,
    'deviceName': 'B',
    'devicePath': '/dev/B',
    'deviceSerial': 'B',
    'dirPath': 'trip/$name',
    'fileType': 'image',
  };

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  setUp(() async {
    downloads = [];
    failing = {};
    favorites = [];
    // Before the host is set: the shared client is built once per host and
    // kept (#1782), so it has to come from this factory.
    sharedHttpClientFactory = () => MockClient((request) async {
      final url = request.url;
      switch (url.path) {
        case '/api/v0/storage/devices/status':
          return http.Response(
            jsonEncode({
              'devices': [device('A'), device('B', serial: 'B')],
            }),
            200,
          );
        // Files lists trip/ on B; A's photo.jpg sits at the same path.
        case '/api/v0/files':
          return http.Response(
            jsonEncode([onB('z.jpg'), onB('photo.jpg'), onB('a.jpg')]),
            200,
          );
        case '/api/v0/files/download':
          try {
            final bytes = read(
              url.queryParameters['serial'],
              url.queryParameters['filePath']!,
            );
            return http.Response.bytes(bytes, 200);
          } on ApiException catch (e) {
            return http.Response('', e.statusCode);
          }
        case '/api/v0/photos/favorite':
          favorites.add(jsonDecode(request.body) as Map<String, Object?>);
          return http.Response('{"isFavorite": true}', 200);
        case '/api/v0/photos/metadata':
          return http.Response('{}', 404);
      }
      return http.Response(url.path.endsWith('/health') ? '{}' : '[]', 200);
    });
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    await AppSettings.instance.addHost(
      HostEntry(name: 'Test', hostAddress: 'http://localhost:8080'),
    );
    PhotoBytesCache.instance.clear();
    StorageService.invalidateDeviceCache();
  });

  tearDown(() {
    PhotoBytesCache.instance.clear();
    StorageService.invalidateDeviceCache();
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  /// Whether [settle] lets real time pass. Photos needs it for the thumbnails
  /// and the photo to decode; under Files it would let the folder's caches
  /// reach for platform directories a test has none of.
  var realAsync = true;

  /// Lets downloads answer and the photo decode, then pumps through any route
  /// transition. Photos keeps a hint animating, so nothing ever settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < (realAsync ? 3 : 0); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // ── Photos ─────────────────────────────────────────────────────────────────

  final trip = PhotoAlbum(
    id: 7,
    name: 'Trip',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    itemCount: 3,
  );

  PhotoAlbumItem albumItem(int id, String serial, String relPath) =>
      PhotoAlbumItem(
        id: id,
        albumId: trip.id,
        deviceSerial: serial,
        relPath: relPath,
        addedAt: DateTime(2026),
      );

  /// Image matches for a search of "photo", newest first. The photos list
  /// returns images only, so the video that shares the name is absent.
  final searchMatches = <wire.PhotoItem>[
    wire.PhotoItem(
      relPath: 'trip/photo.jpg',
      fileName: 'photo.jpg',
      size: 1,
      mtime: DateTime(2026).millisecondsSinceEpoch,
      serial: 'A',
    ),
    wire.PhotoItem(
      relPath: 'trip/photo.jpg',
      fileName: 'photo.jpg',
      size: 1,
      mtime: DateTime(2025).millisecondsSinceEpoch,
      serial: 'B',
    ),
    wire.PhotoItem(
      relPath: 'trip/photo_old.jpg',
      fileName: 'photo_old.jpg',
      size: 1,
      mtime: DateTime(2024).millisecondsSinceEpoch,
      serial: 'B',
    ),
  ];

  /// A Photos page over the two-device library: 364 photos fetched 50 at a
  /// time, A's photo.jpg then B's at the top; an album holding both; and a
  /// search that finds both photo.jpg copies and photo_old.jpg.
  Future<PhotosController> pumpPhotos(
    WidgetTester tester, {
    String? album,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = PhotosController(
      isWeb: true,
      listCache: PhotosListCache(),
      albumsCache: AlbumsCache(),
      activeHost: () => 'http://localhost:8080',
      getPhotos:
          ({
            int offset = 0,
            int limit = 50,
            String? serial,
            PhotoSortField sort = PhotoSortField.added,
            PhotoSortOrder order = PhotoSortOrder.desc,
            String? q,
          }) async {
            final query = q?.trim().toLowerCase() ?? '';
            final all = query.isEmpty
                ? <wire.PhotoItem>[
                    for (var i = 0; i < 364; i++)
                      switch (i) {
                        0 || 1 => wire.PhotoItem(
                          relPath: 'trip/photo.jpg',
                          fileName: 'photo.jpg',
                          size: 1,
                          mtime: 0,
                          serial: i == 0 ? 'A' : 'B',
                        ),
                        _ => wire.PhotoItem(
                          relPath: 'camera/$i.jpg',
                          fileName: '$i.jpg',
                          size: 1,
                          mtime: 0,
                          serial: 'A',
                        ),
                      },
                  ]
                : [
                    for (final photo in searchMatches)
                      if (photo.fileName.toLowerCase().contains(query)) photo,
                  ];
            final start = offset.clamp(0, all.length);
            final end = (start + limit).clamp(start, all.length);
            return wire.PaginatedPhotosResponse(
              photos: all.sublist(start, end),
              total: all.length,
              offset: start,
              limit: limit,
            );
          },
      listFavoriteKeys: () async => {},
      listAlbums: ({bool tree = false}) async => [trip],
      listAlbumItems:
          (
            int albumId, {
            PhotoSortField sort = PhotoSortField.added,
            PhotoSortOrder order = PhotoSortOrder.desc,
          }) async => [
            albumItem(1, 'A', 'trip/photo.jpg'),
            albumItem(2, 'B', 'trip/photo.jpg'),
            albumItem(3, 'A', 'trip/sunset.jpg'),
          ],
      downloadFileBytes: (path, {String? serial, String? fileName}) async =>
          read(serial, path),
      // A bundled sample for every tile, so the grid makes no request.
      thumbnailUrl: (path, {String? serial, String? size}) => Uri(
        scheme: DemoPhotosService.assetScheme,
        path: '${DemoPhotosService.assetDir}/aurora.jpg',
      ),
      searchDelay: Duration.zero,
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: PhotosPage(album: album, controller: controller),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await settle(tester);
    return controller;
  }

  /// Taps B's photo.jpg in the grid, past the double-tap window so the tap
  /// lands as one.
  Future<void> tapBPhoto(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('photo_tile_B:trip/photo.jpg')));
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
  }

  // ── Files ──────────────────────────────────────────────────────────────────

  /// Pumps the app's real `/view` route beside Files at [location].
  Future<GoRouter> pumpRouted(WidgetTester tester, String location) async {
    realAsync = false;
    addTearDown(() => realAsync = true);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: location,
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
    // The folder listing's timers must not outlive the test.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await settle(tester);
    return router;
  }

  // ── The matrix ─────────────────────────────────────────────────────────────

  /// Each entry point: how it opens B's photo.jpg, the photos either side of
  /// it in the order that entry point shows them, and the counter's total.
  final entryPoints =
      <
        String,
        ({
          Future<void> Function(WidgetTester tester) open,
          List<String> around,
          int position,
          int total,
        })
      >{
        'the Photos grid': (
          open: (tester) async {
            await pumpPhotos(tester);
            await tapBPhoto(tester);
          },
          around: ['A:trip/photo.jpg', 'B:trip/photo.jpg', 'A:camera/2.jpg'],
          position: 2,
          total: 364,
        ),
        'a Photos search result': (
          open: (tester) async {
            await pumpPhotos(tester);
            await tester.tap(find.byKey(const ValueKey('photos_search')));
            await tester.pump();
            await tester.enterText(
              find.descendant(
                of: find.byType(PhotosSearchBar),
                matching: find.byType(TextField),
              ),
              'photo',
            );
            await settle(tester);
            await tapBPhoto(tester);
          },
          around: [
            'A:trip/photo.jpg',
            'B:trip/photo.jpg',
            'B:trip/photo_old.jpg',
          ],
          position: 2,
          total: 3,
        ),
        'an album': (
          open: (tester) async {
            await pumpPhotos(tester, album: 'Trip');
            await tapBPhoto(tester);
          },
          around: ['A:trip/photo.jpg', 'B:trip/photo.jpg', 'A:trip/sunset.jpg'],
          position: 2,
          total: 3,
        ),
        'Files': (
          open: (tester) async {
            await pumpRouted(tester, '/files/trip');
            await tester.tap(find.text('photo.jpg'));
            await settle(tester);
          },
          around: ['B:trip/a.jpg', 'B:trip/photo.jpg', 'B:trip/z.jpg'],
          position: 2,
          total: 3,
        ),
        'a /view deep link': (
          open: (tester) => pumpRouted(tester, '/view/trip/photo.jpg?serial=B'),
          around: ['B:trip/a.jpg', 'B:trip/photo.jpg', 'B:trip/z.jpg'],
          position: 2,
          total: 3,
        ),
      };

  /// The hash of the photo on screen.
  String shown(WidgetTester tester) =>
      hash(tester.widget<CurrentPhoto>(find.byType(CurrentPhoto)).bytes);

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await settle(tester);
  }

  for (final MapEntry(key: from, value: entry) in entryPoints.entries) {
    final (:open, :around, :position, :total) = entry;
    final [before, tapped, after] = around;

    group('opened from $from', () {
      testWidgets('shows the tapped photo from its own device', (tester) async {
        await paintPhotos(tester);
        await open(tester);

        expect(find.byType(ImageViewerPage), findsOneWidget);
        expect(downloads.first, tapped, reason: 'asked for B, not A');
        expect(shown(tester), hash(pictures[tapped]!));
        expect(
          tester.widget<ImageViewerPage>(find.byType(ImageViewerPage)).serial,
          'B',
        );
        expect(find.text('$position / $total'), findsOneWidget);
      });

      testWidgets('the arrow keys step through the list as it is shown', (
        tester,
      ) async {
        await paintPhotos(tester);
        await open(tester);

        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(shown(tester), hash(pictures[after]!));
        expect(find.text('${position + 1} / $total'), findsOneWidget);

        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(shown(tester), hash(pictures[tapped]!));
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(shown(tester), hash(pictures[before]!));
        expect(find.text('${position - 1} / $total'), findsOneWidget);
      });

      testWidgets('f and Escape answer without a tap first', (tester) async {
        await paintPhotos(tester);
        await open(tester);

        await press(tester, LogicalKeyboardKey.keyF);
        expect(favorites, [
          {'relPath': 'trip/photo.jpg', 'deviceSerial': 'B'},
        ]);

        await press(tester, LogicalKeyboardKey.escape);
        expect(find.byType(ImageViewerPage), findsNothing);
      });

      testWidgets('a full-size photo that fails offers a retry and keeps the '
          'photo on screen', (tester) async {
        await paintPhotos(tester);
        failing.add(after);
        await open(tester);

        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(
          find.text(Errors.message(const ApiException(500), 'load the photo')),
          findsOneWidget,
        );
        expect(shown(tester), hash(pictures[tapped]!), reason: 'never black');
        expect(find.text('$position / $total'), findsOneWidget);

        failing.clear();
        await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
        await settle(tester);
        expect(shown(tester), hash(pictures[after]!));
        expect(find.text('${position + 1} / $total'), findsOneWidget);
      });
    });
  }

  testWidgets('a video among the search results never opens the photo '
      'viewer', (tester) async {
    await paintPhotos(tester);
    await entryPoints['a Photos search result']!.open(tester);
    await press(tester, LogicalKeyboardKey.escape);

    expect(find.byKey(const ValueKey('photo_tile_B:trip/photo.jpg')), findsOne);
    expect(
      find.byKey(const ValueKey('photo_tile_B:trip/photo.mp4')),
      findsNothing,
    );
  });
}
