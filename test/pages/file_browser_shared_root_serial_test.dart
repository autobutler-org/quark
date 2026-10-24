import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/router.dart' as app;
import 'package:quark/router.dart' show AppRoutes;
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #3727: a share on a USB drive opens on that drive. Picking it in Shared
/// with me used to keep only its path, so the stat asked the internal drive,
/// which has no such file.
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

  late List<Uri> requested;

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
    sharedHttpClientFactory = () => MockClient((request) async {
      requested.add(request.url);
      final url = request.url;
      if (url.path.endsWith('/storage/devices/status')) {
        return http.Response(
          jsonEncode({
            'devices': [device('A'), device('B', serial: 'ABC123')],
          }),
          200,
        );
      }
      if (url.path.endsWith('/api/v0/access/mine')) {
        return http.Response(
          jsonEncode({
            'items': [
              for (final relPath in ['bob/report.pdf', 'bob/Trip'])
                {
                  'relPath': relPath,
                  'deviceSerial': 'ABC123',
                  'level': 'read',
                  'owner': 'bob',
                },
            ],
          }),
          200,
        );
      }
      if (url.path.endsWith('/api/v0/files/stat')) {
        // Only the stick has them.
        if (url.queryParameters['serial'] != 'ABC123') {
          return http.Response('{"error":"not found"}', 404);
        }
        final isDir = !url.queryParameters['filePath']!.endsWith('.pdf');
        return http.Response(
          jsonEncode({
            'isDir': isDir,
            'fileType': isDir ? 'folder' : 'pdf',
            'name': isDir ? 'Trip' : 'report.pdf',
          }),
          200,
        );
      }
      return http.Response(url.path.endsWith('/health') ? '{}' : '[]', 200);
    });
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    await AppSettings.instance.addHost(
      HostEntry(name: 'Test', hostAddress: 'http://localhost:8080'),
    );
    await AppSettings.instance.setUsername('alice');
    StorageService.invalidateDeviceCache();
  });

  tearDown(() async {
    await AppSettings.instance.setUsername(null);
    StorageService.invalidateDeviceCache();
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  /// Pumps the app's real `/files` routes beside a stub viewer, opens Shared
  /// with me and picks [relPath].
  Future<GoRouter> pickShare(WidgetTester tester, String relPath) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/files',
      routes: [
        GoRoute(
          path: '/view/:path(.*)',
          builder: (_, _) => const Scaffold(body: Text('viewer')),
        ),
        app.router.configuration.routes.whereType<GoRoute>().firstWhere(
          (route) => route.path == AppRoutes.files,
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(
      find.byKey(const ValueKey('file_shortcut_shared_with_me')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('shared_root_$relPath')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    return router;
  }

  testWidgets('a shared file on a USB drive opens on that drive', (
    tester,
  ) async {
    final router = await pickShare(tester, 'bob/report.pdf');

    final stats = requested.where((u) => u.path.endsWith('/api/v0/files/stat'));
    expect(stats.map((u) => u.queryParameters['serial']), contains('ABC123'));
    final location = router.routeInformationProvider.value.uri;
    expect(location.path, '/view/bob/report.pdf');
    expect(location.queryParameters['serial'], 'ABC123');
  });

  testWidgets('a shared folder on a USB drive lists only that drive', (
    tester,
  ) async {
    final router = await pickShare(tester, 'bob/Trip');

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/files/bob/Trip?serial=ABC123',
    );
    final listings = requested.where(
      (u) =>
          u.path.endsWith('/api/v0/files') &&
          u.queryParameters['rootDir'] == 'bob/Trip',
    );
    expect(listings, isNotEmpty);
    expect(
      listings.map((u) => u.queryParametersAll['serial']),
      everyElement(['ABC123']),
    );
  });
}
