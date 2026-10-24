import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/file_browser_page.dart';
import 'package:quark/pages/file_viewer_page.dart';
import 'package:quark/router.dart' as app;
import 'package:quark/router.dart' show AppRoutes;
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/decode_once_image.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_browser_list_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #3355: after a photo was opened from Files and the viewer closed, the
/// list's thumbnails sat one row off — the 0004 row showed 0005's picture.
/// Each test lists a folder of images, opens one in the app's real `/view`
/// route, closes it, and reads which file every row's thumbnail asks for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final names = [for (var i = 1; i <= 8; i++) 'files-photo-000$i.jpg'];

  Map<String, Object?> device(String name, {String serial = ''}) => {
    'name': name,
    'devicePath': '/dev/$name',
    'mountPoint': '/mnt/$name',
    'isInternal': serial.isEmpty,
    'isEnabled': true,
    if (serial.isNotEmpty) 'usbInfo': {'serial': serial},
  };

  Map<String, Object?> image(String name, String serial) => {
    'name': name,
    'size': 12,
    'isDir': false,
    'deviceName': serial.isEmpty ? 'A' : serial,
    'devicePath': '/dev/${serial.isEmpty ? 'A' : serial}',
    'deviceSerial': serial,
    'dirPath': 'users/me/$name',
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

  Future<void> setUpHost(String serial) async {
    sharedHttpClientFactory = () => MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/storage/devices/status')) {
        return http.Response(
          jsonEncode({
            'devices': [device('A'), device('B', serial: 'B')],
          }),
          200,
        );
      }
      if (path.endsWith('/api/v0/files')) {
        return http.Response(
          jsonEncode([for (final name in names) image(name, serial)]),
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
  }

  tearDown(() {
    StorageService.invalidateDeviceCache();
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  Future<GoRouter> pumpRouted(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/files/users/me',
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

  /// Every list row's file, and the thumbnail its leading draws: keyed by
  /// that file's device and path, loading that file's URL, and decoded once
  /// so the list coming back from the viewer cannot re-decode it into
  /// another row's picture.
  void expectThumbnailsOnTheirRows(WidgetTester tester) {
    final tiles = find.byType(FileBrowserListTile);
    expect(tiles, findsNWidgets(names.length));
    for (final element in tiles.evaluate()) {
      final item = (element.widget as FileBrowserListTile).item;
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byWidget(element.widget),
          matching: find.byType(Image),
        ),
      );
      expect(image.key, ValueKey('${item.deviceSerial}:${item.apiPath}'));
      expect(image.image, isA<DecodeOnceImage>());
      final cached =
          ((image.image as DecodeOnceImage).image as ResizeImage).imageProvider
              as CachedNetworkImageProvider;
      final url = Uri.parse(cached.url);
      expect(url.path, endsWith('/thumbnails/${item.apiPath}'));
      expect(url.queryParameters['serial'] ?? '', item.deviceSerial);
    }
  }

  for (final serial in ['', 'B']) {
    final where = serial.isEmpty ? 'the built-in drive' : 'device $serial';
    testWidgets('closing the viewer leaves each thumbnail on its row '
        '($where)', (tester) async {
      await setUpHost(serial);
      final router = await pumpRouted(tester);
      expectThumbnailsOnTheirRows(tester);

      await tester.tap(find.text('files-photo-0004.jpg'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(router.state.uri.path, '/view/users/me/files-photo-0004.jpg');
      expect(find.byType(FileViewerPage), findsOneWidget);

      // The viewer's own close, the X in its app bar.
      final viewer = tester.state(find.byType(FileViewerPage));
      Router.neglect(
        viewer.context,
        () => viewer.context.go(
          AppRoutes.containingFolder(
            'users/me/files-photo-0004.jpg',
            serial: serial,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(router.state.uri.path, '/files/users/me');

      expectThumbnailsOnTheirRows(tester);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
    });
  }
}
