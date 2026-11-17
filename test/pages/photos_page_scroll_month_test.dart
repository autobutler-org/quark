import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/models/paginated_photos_response.dart' as wire;
import 'package:quark/models/photo_sort.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/fake_thumbnail_store.dart';
import '../support/tap_target_guidelines.dart' show setViewport;

const _count = 120;

/// Ten days apart, so the library spans several months.
int _mtime(int i) =>
    DateTime.utc(2025, 6, 28).millisecondsSinceEpoch ~/ 1000 - i * 10 * 86400;

/// #4155: scrolling the Photos grid puts nothing over the photos. The pinned
/// month header is the only month the grid names while it scrolls; no label
/// floats at the edge of the grid.
void main() {
  // The test platform is Android, so the page also asks photo_manager for the
  // device library; denying it lets the page settle.
  const photoManager = MethodChannel('com.fluttercandies/photo_manager');
  TestWidgetsFlutterBinding.ensureInitialized();

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
                  relPath: '/photos/p$i.jpg',
                  fileName: 'p$i.jpg',
                  size: 1,
                  mtime: _mtime(i),
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

  /// Every text naming a month, such as "May 2025".
  Finder monthTexts() => find.byWidgetPredicate(
    (w) => w is Text && RegExp(r'^[A-Z][a-z]+ \d{4}$').hasMatch(w.data ?? ''),
  );

  for (final (label, size) in [
    ('phone', const Size(390, 844)),
    ('desktop', const Size(1440, 900)),
  ]) {
    testWidgets('$label: a scroll shows no month label over the photos', (
      tester,
    ) async {
      ThumbnailCacheManager.instance = FakeThumbnailStore(
        (_) => throw StateError('no thumbnails in this test'),
      );
      setViewport(tester, size);
      await tester.pumpWidget(
        MaterialApp(home: PhotosPage(controller: library())),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(PhotoGridTile), findsWidgets);

      // Mid-drag, with the finger still down, is when a floating label
      // would show.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PhotoGridTile).first),
      );
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, -120));
        await tester.pump(const Duration(milliseconds: 16));
      }

      final shown = monthTexts();
      expect(shown, findsWidgets, reason: 'the pinned header names a month');
      for (final element in shown.evaluate()) {
        expect(
          find.ancestor(
            of: find.byWidget(element.widget),
            matching: find.byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith(
                    'photo_grid_section_',
                  ),
            ),
          ),
          findsOneWidget,
          reason:
              '"${(element.widget as Text).data}" is shown outside a '
              'month header',
        );
      }

      await gesture.up();
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
