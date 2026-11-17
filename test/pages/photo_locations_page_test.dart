import 'dart:convert';

import 'package:flutter_map/flutter_map.dart'
    show DisabledMapCachingProvider, FlutterMap;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/photo_locations_controller.dart';
import 'package:quark/models/photo_locations.dart';
import 'package:quark/models/photo_map_tiles.dart';
import 'package:quark/pages/photo_locations_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:quark/utils/photo_map_config.dart';
import 'package:quark/widgets/photo_locations/location_cluster_marker.dart';
import 'package:quark/widgets/photo_locations/photo_map_preview.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/fake_thumbnail_store.dart';
import '../support/tap_target_guidelines.dart' show setViewport;

/// A 1×1 PNG, for every tile and thumbnail.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

PhotoLocationPoint _point(String path, double lat, double lon, int year) =>
    PhotoLocationPoint(
      serial: '',
      relPath: path,
      fileName: path.split('/').last,
      latitude: lat,
      longitude: lon,
      takenAt: DateTime.utc(year, 6, 15),
      modified: DateTime.utc(2026),
    );

/// Photos at distinctive positions, so a leak of any of them at any
/// precision shows up in a request.
final _points = [
  _point('lake/a.jpg', 56.81234, -5.10987, 2024),
  _point('lake/b.jpg', 56.81239, -5.10981, 2026),
  _point('edi/c.jpg', 55.94861, -3.19972, 2025),
];

const _locations = PhotoLocations(
  points: [],
  total: 5,
  located: 3,
  unlocated: 2,
  pending: 1,
);

/// Every way a photo's position could be spelled in a request: each
/// coordinate at 2 to 6 decimal places, signed and not.
Iterable<String> _spellings() sync* {
  for (final p in _points) {
    for (var dp = 2; dp <= 6; dp++) {
      for (final v in [p.latitude, p.longitude]) {
        final s = v.toStringAsFixed(dp);
        yield s;
        yield s.replaceFirst('-', '');
      }
    }
  }
}

/// Everything that left the app: each request's URL, headers and body.
String _outbound(List<http.BaseRequest> requests) => [
  for (final r in requests) ...[
    r.url.toString(),
    ...r.headers.entries.map((e) => '${e.key}: ${e.value}'),
    if (r is http.Request) r.body,
  ],
].join('\n');

void main() {
  final settings = AppSettings.instance;
  late List<http.BaseRequest> requests;
  late http.Client client;
  late FakeThumbnailStore thumbnails;

  setUp(() {
    requests = [];
    client = MockClient((request) async {
      requests.add(request);
      return http.Response.bytes(
        _png,
        200,
        headers: {'content-type': 'image/png'},
      );
    });
    // Reading the real store first would open a disk cache, which a test
    // has no plugin for; each test file runs in its own isolate.
    thumbnails = FakeThumbnailStore.of(_png);
    ThumbnailCacheManager.instance = thumbnails;
    final enabled = settings.photoMapEnabled.value;
    final tiles = settings.photoMapTiles.value;
    final custom = settings.photoMapCustomTileUrl.value;
    addTearDown(() {
      settings.photoMapEnabled.value = enabled;
      settings.photoMapTiles.value = tiles;
      settings.photoMapCustomTileUrl.value = custom;
    });
  });

  Future<PhotoLocationsController> pumpPage(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    LatLng? focus,
  }) async {
    final controller = PhotoLocationsController(
      fetchLocations: () async => PhotoLocations(
        points: _points,
        total: _locations.total,
        located: _locations.located,
        unlocated: _locations.unlocated,
        pending: _locations.pending,
      ),
      thumbnailUrl: (path, {serial, size}) =>
          Uri.parse('https://quark.test/api/v0/thumbnails/$path'),
    );
    addTearDown(controller.dispose);
    setViewport(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: PhotoLocationsPage(
          controller: controller,
          focus: focus,
          httpClient: client,
          cachingProvider: const DisabledMapCachingProvider(),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    return controller;
  }

  /// The attribution is on screen, whole, inside the viewport.
  void expectAttribution(WidgetTester tester, Size size) {
    final text = find.text(PhotoMapConfig.attribution);
    expect(text, findsWidgets);
    for (final element in text.evaluate()) {
      final box = element.renderObject! as RenderBox;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      expect(
        rect.left >= 0 &&
            rect.right <= size.width &&
            rect.bottom <= size.height,
        isTrue,
        reason: 'attribution at $rect is outside $size',
      );
      final paragraph = element.renderObject! as RenderParagraph;
      expect(paragraph.didExceedMaxLines, isFalse, reason: 'clipped');
    }
  }

  testWidgets('no photo position leaves in a tile request, from this Quark', (
    tester,
  ) async {
    settings.photoMapEnabled.value = true;
    settings.photoMapTiles.value = PhotoMapTiles.quark;
    await pumpPage(tester, focus: const LatLng(56.8, -5.1));

    expect(requests, isNotEmpty, reason: 'the map fetched no tiles');
    for (final r in requests) {
      expect(
        r.url.path,
        matches(RegExp(r'^/api/v0/photos/map-tiles/\d+/\d+/\d+$')),
      );
      expect(r.url.query, isEmpty);
    }
    final outbound = [_outbound(requests), ...thumbnails.fetched].join('\n');
    for (final s in _spellings()) {
      expect(outbound, isNot(contains(s)), reason: 'leaked $s');
    }
  });

  testWidgets('opted into OpenStreetMap, the tiles carry no position and '
      'no Quark session', (tester) async {
    settings.photoMapEnabled.value = true;
    settings.photoMapTiles.value = PhotoMapTiles.openStreetMap;
    await pumpPage(tester, focus: const LatLng(56.8, -5.1));

    expect(requests, isNotEmpty);
    for (final r in requests) {
      expect(r.url.host, 'tile.openstreetmap.org');
      expect(
        r.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(
        r.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('cookie')),
      );
    }
    final outbound = _outbound(requests);
    for (final s in _spellings()) {
      expect(outbound, isNot(contains(s)), reason: 'leaked $s');
    }
  });

  testWidgets('with the map off, no tile is ever requested', (tester) async {
    settings.photoMapEnabled.value = false;
    await pumpPage(tester);

    expect(requests, isEmpty);
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.byKey(const ValueKey('photo_locations_view')), findsNothing);
    // The list stands in, so the photos are still reachable.
    expect(find.textContaining('Cluster of 2 photos'), findsWidgets);
  });

  for (final size in const [Size(390, 844), Size(360, 640), Size(1280, 800)]) {
    testWidgets('the attribution is whole on the map at $size', (tester) async {
      settings.photoMapEnabled.value = true;
      settings.photoMapTiles.value = PhotoMapTiles.quark;
      await pumpPage(tester, size: size);
      expectAttribution(tester, size);
      expect(
        find.text(
          '3 of 5 photos have a location · 2 have none · '
          'still reading 1, so more may appear',
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('a phone opens a cluster in a bottom sheet, Back closes it', (
    tester,
  ) async {
    settings.photoMapEnabled.value = true;
    final controller = await pumpPage(tester, focus: const LatLng(56.8, -5.1));

    await tester.tap(find.byType(LocationClusterMarker).first);
    // A marker also takes a double tap, so a single one lands after the
    // double-tap timeout.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('photo_locations_sheet')), findsOneWidget);
    expect(controller.selected, isNotNull);
    expect(
      find.byKey(ValueKey('photo_tile_${controller.selected!.cover.id}')),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(controller.selected, isNull);
    expect(find.byKey(const ValueKey('photo_locations_sheet')), findsNothing);
  });

  testWidgets('a wide screen opens a cluster in a pane, Escape closes it', (
    tester,
  ) async {
    settings.photoMapEnabled.value = true;
    final controller = await pumpPage(
      tester,
      size: const Size(1280, 800),
      focus: const LatLng(56.8, -5.1),
    );

    await tester.tap(find.byType(LocationClusterMarker).first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('photo_locations_pane')), findsOneWidget);
    expect(controller.selectedPhotos.map((p) => p.id), [
      for (final p in controller.selected!.points) p.id,
    ]);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const ValueKey('photo_locations_pane')), findsNothing);
  });

  testWidgets('markers are named for a screen reader', (tester) async {
    settings.photoMapEnabled.value = true;
    await pumpPage(tester, focus: const LatLng(56.81, -5.11));
    expect(
      find.bySemanticsLabel('Cluster of 2 photos, June 2024 to June 2026'),
      findsOneWidget,
    );
  });

  testWidgets('the viewer preview shows the attribution and leaks nothing', (
    tester,
  ) async {
    const size = Size(360, 640);
    setViewport(tester, size);
    final p = _points.first;
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: PhotoMapPreview(
              latitude: p.latitude,
              longitude: p.longitude,
              tiles: PhotoMapTiles.quark,
              httpClient: client,
              cachingProvider: const DisabledMapCachingProvider(),
              onOpen: () => opened = true,
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expectAttribution(tester, size);
    expect(requests, isNotEmpty);
    final outbound = _outbound(requests);
    for (final s in _spellings()) {
      expect(outbound, isNot(contains(s)), reason: 'leaked $s');
    }
    await tester.tap(find.byKey(const ValueKey('photo_map_preview_open')));
    expect(opened, isTrue);
  });
}
