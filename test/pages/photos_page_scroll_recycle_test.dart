import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/models/paginated_photos_response.dart' as wire;
import 'package:quark/models/photo_sort.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/fake_thumbnail_store.dart';
import '../support/tap_target_guidelines.dart' show setViewport;

/// Serves every thumbnail from memory: a distinct, decodable PNG per photo,
/// filled with that photo's own color, so a tile showing a neighbor's picture
/// is as visible as one showing none.
///
/// A file name in [failNext] has its next fetch answer 503, as the Quark does
/// when its IO semaphore times out.
FakeThumbnailStore _store(
  Map<String, Uint8List> images, {
  Set<String>? failNext,
}) => FakeThumbnailStore((url) {
  final name = _nameOf(url);
  if (failNext?.remove(name) ?? false) {
    throw HttpExceptionWithStatus(
      503,
      'Service Unavailable',
      uri: Uri.parse(url),
    );
  }
  return images[name]!;
});

/// The photo file name a thumbnail [url] asks for.
String _nameOf(String url) => Uri.parse(url).pathSegments.last;

const _count = 300;

String _name(int i) => 'p$i.png';

/// A color of its own for photo [i], far enough from its neighbors' that a
/// mixed-up tile reads as wrong.
Color _color(int i) => Color.fromARGB(
  255,
  (i * 67) % 256,
  (i * 131 + 40) % 256,
  (i * 29 + 90) % 256,
);

Future<Uint8List> _png(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final image = await recorder.endRecording().toImage(8, 8);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// The color at the middle of [image].
Future<Color> _centerColor(ui.Image image) async {
  final bytes = (await image.toByteData())!;
  final offset = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
  return Color.fromARGB(
    bytes.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
}

/// #3349: after scrolling the Photos grid away and back, every tile that had
/// shown its thumbnail shows it again, its own one, rather than painting
/// black. Earlier: #2082. The tiles that leave are disposed, and the image
/// cache is held small enough that their decoded pictures are evicted, so
/// coming back has to load each one again.
void main() {
  // The test platform is Android, so the page also asks photo_manager for the
  // device library; denying it lets the page settle.
  const photoManager = MethodChannel('com.fluttercandies/photo_manager');
  TestWidgetsFlutterBinding.ensureInitialized();
  final images = <String, Uint8List>{};

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

  PhotosController library() => PhotosController(
    getPhotos:
        ({
          int offset = 0,
          int limit = 0,
          String? serial,
          sort = PhotoSortField.added,
          order = PhotoSortOrder.desc,
          String? q,
        }) async {
          final end = limit == 0 ? _count : (offset + limit).clamp(0, _count);
          return wire.PaginatedPhotosResponse(
            photos: [
              for (var i = offset; i < end; i++)
                wire.PhotoItem(
                  relPath: '/photos/${_name(i)}',
                  fileName: _name(i),
                  size: 1,
                  mtime: _count - i,
                  serial: '',
                ),
            ],
            total: _count,
            offset: offset,
            limit: limit,
          );
        },
    activeHost: () => 'quark.local',
    listFavoriteKeys: () async => <String>{},
    loadDeviceAssets: () async => [],
    listAlbums: ({bool tree = true}) async => [],
    listDevices: () async => [],
    thumbnailUrl: (path, {serial, size}) =>
        Uri.parse('http://quark.local/api/v0/thumbnails$path'),
    searchFiles: null,
  );

  /// Lets real decoding and the fake store's futures run, a frame at a time.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Finder tileOf(String name) =>
      find.byWidgetPredicate((w) => w is PhotoGridTile && w.item.name == name);

  /// The names of the photos whose tiles are wholly on screen.
  List<String> onScreen(WidgetTester tester) {
    final screen = Offset.zero & tester.view.physicalSize;
    return [
      for (final element in find.byType(PhotoGridTile).evaluate())
        if (screen.contains(tester.getTopLeft(find.byWidget(element.widget))) &&
            screen.contains(
              tester.getBottomRight(find.byWidget(element.widget)) -
                  const Offset(1, 1),
            ))
          (element.widget as PhotoGridTile).item.name,
    ];
  }

  /// Fails unless the tile for [name] paints a picture, and that picture is
  /// [name]'s own.
  Future<void> expectShowsOwnThumbnail(WidgetTester tester, String name) async {
    final raw = find.descendant(
      of: tileOf(name),
      matching: find.byType(RawImage),
    );
    expect(raw, findsOneWidget, reason: '$name has no image widget');
    final image = tester.widget<RawImage>(raw).image;
    expect(image, isNotNull, reason: '$name paints no picture');
    expect(image!.debugDisposed, isFalse, reason: "$name's picture is gone");
    final color = await tester.runAsync(() => _centerColor(image));
    final i = int.parse(name.substring(1, name.indexOf('.')));
    expect(color, _color(i), reason: "$name shows another photo's picture");
  }

  Future<ScrollPosition> pumpPage(
    WidgetTester tester,
    FakeThumbnailStore store,
    Size size,
  ) async {
    if (images.isEmpty) {
      await tester.runAsync(() async {
        for (var i = 0; i < _count; i++) {
          images[_name(i)] = await _png(_color(i));
        }
      });
    }
    ThumbnailCacheManager.instance = store;
    setViewport(tester, size);
    final cacheSize = imageCache.maximumSize;
    imageCache
      ..clear()
      ..clearLiveImages()
      ..maximumSize = 20;
    addTearDown(() {
      imageCache
        ..clear()
        ..clearLiveImages()
        ..maximumSize = cacheSize;
    });
    await tester.pumpWidget(
      MaterialApp(home: PhotosPage(controller: library())),
    );
    await settle(tester);
    return tester
        .state<ScrollableState>(
          find
              .ancestor(
                of: find.byType(PhotoGridTile).first,
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
  }

  for (final (label, size) in [
    ('phone', const Size(390, 844)),
    ('desktop', const Size(1440, 900)),
  ]) {
    testWidgets('$label: tiles reload their thumbnails after scrolling away '
        'and back', (tester) async {
      final store = _store(images);
      final position = await pumpPage(tester, store, size);

      final first = onScreen(tester);
      expect(first.length, greaterThan(4));
      for (final name in first) {
        await expectShowsOwnThumbnail(tester, name);
      }

      // Far enough that the first screen leaves the viewport and its cache
      // extent, so those tiles are disposed and their pictures evicted.
      // A page at a time, so the grid loads the pages it scrolls into.
      for (var i = 1; i <= 4; i++) {
        position.jumpTo((size.height * i).clamp(0, position.maxScrollExtent));
        await settle(tester);
      }
      expect(position.pixels, greaterThan(size.height * 2));
      for (final name in first) {
        expect(tileOf(name), findsNothing, reason: '$name was never disposed');
      }

      position.jumpTo(0);
      await settle(tester);

      for (final name in first) {
        // Fetched again: its decoded picture really was evicted.
        expect(store.fetched.map(_nameOf).where((n) => n == name).length, 2);
        await expectShowsOwnThumbnail(tester, name);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('$label: a tile whose reload answers 503 retries and ends on '
        'its thumbnail', (tester) async {
      final failNext = <String>{};
      final store = _store(images, failNext: failNext);
      final position = await pumpPage(tester, store, size);
      final first = onScreen(tester);
      final victim = first.first;

      for (var i = 1; i <= 4; i++) {
        position.jumpTo((size.height * i).clamp(0, position.maxScrollExtent));
        await settle(tester);
      }
      expect(tileOf(victim), findsNothing);

      failNext.add(victim);
      position.jumpTo(0);
      await settle(tester);
      // Long enough for any retry to come round.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
        await settle(tester);
      }

      // Loaded, refused while busy, then loaded again.
      expect(store.fetched.map(_nameOf).where((n) => n == victim).length, 3);
      await expectShowsOwnThumbnail(tester, victim);
      expect(tester.takeException(), isNull);
    });
  }
}
