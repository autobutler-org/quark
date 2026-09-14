import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/demo_photos_service.dart';

import '../support/unreachable_quark.dart';

/// #1746: with Demo mode on, the Photos page shows the bundled sample library
/// and talks to no Quark at all; with it off, nothing from the sample library
/// is rendered. Both halves matter — the second is the one that protects a
/// real user from seeing photos that are not theirs.
void main() {
  const desktopSize = Size(1400, 900);
  final settings = AppSettings.instance;

  late HttpOverrides? priorOverrides;
  late _RecordingHttpOverrides recorder;

  // The test platform is Android, so the page also asks photo_manager for the
  // device library. With no plugin behind the channel that call never answers
  // and the whole refresh hangs; denying it lets the page settle.
  const photoManager = MethodChannel('com.fluttercandies/photo_manager');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          photoManager,
          (_) async => throw MissingPluginException(),
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(photoManager, null);
  });

  setUp(() async {
    priorOverrides = HttpOverrides.current;
    recorder = _RecordingHttpOverrides();
    HttpOverrides.global = recorder;
    await settings.addHost(
      HostEntry(name: 'Demo', hostAddress: 'http://quark.test'),
    );
  });

  tearDown(() async {
    HttpOverrides.global = priorOverrides;
    await settings.setDemoMode(false);
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  });

  Future<void> pumpPhotos(WidgetTester tester) async {
    tester.view.physicalSize = desktopSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: PhotosPage()));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder assetImages() => find.byWidgetPredicate(
    (w) => w is Image && w.image is AssetImage,
    description: 'an Image backed by a bundled asset',
  );

  testWidgets('shows the sample library without reaching the Quark', (
    tester,
  ) async {
    await settings.setDemoMode(true);

    await pumpPhotos(tester);

    expect(tester.takeException(), isNull);
    expect(
      assetImages(),
      findsNWidgets(DemoPhotosService.photos.length),
      reason: 'every sample photo gets a tile',
    );
    expect(find.text('Quark: ${DemoPhotosService.photos.length}'), findsOne);
    for (final album in DemoPhotosService.albums()) {
      expect(find.text(album.name), findsOneWidget, reason: album.name);
    }
    expect(find.text('No photos yet'), findsNothing);
    expect(
      recorder.requests,
      isEmpty,
      reason: 'demo mode must not touch the backend',
    );
  });

  testWidgets('renders none of the sample library when off', (tester) async {
    await pumpPhotos(tester);

    expect(tester.takeException(), isNull);
    expect(assetImages(), findsNothing);
    for (final album in DemoPhotosService.albums()) {
      if (album.isSystemAlbum) continue;
      expect(find.text(album.name), findsNothing, reason: album.name);
    }
    expect(
      recorder.requests,
      isNotEmpty,
      reason: 'with demo mode off the page asks the Quark as before',
    );
  });
}

/// Fails every request the way an unreachable Quark does, and remembers that
/// it was asked — the assertion demo mode needs is "nothing was asked".
class _RecordingHttpOverrides extends HttpOverrides {
  final List<Uri> requests = [];

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _RecordingHttpClient(requests);
}

class _RecordingHttpClient implements HttpClient {
  _RecordingHttpClient(this.requests);

  final List<Uri> requests;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    requests.add(url);
    return UnreachableQuarkHttpOverrides()
        .createHttpClient(null)
        .openUrl(method, url);
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => openUrl(method, Uri(scheme: 'http', host: host, port: port, path: path));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
