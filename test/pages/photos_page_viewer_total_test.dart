import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/albums_cache.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/controllers/photos_list_cache.dart';
import 'package:quark/models/paginated_photos_response.dart' as wire;
import 'package:quark/models/photo_sort.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/services/demo_photos_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #3357: opened from a 364-photo library with one page of 50 loaded, the
/// viewer read "41 / 50" and stopped at photo 50, because Photos passed it
/// the loaded count and no way to load more.
void main() {
  // 64x64 solid PNG — the viewer needs bytes it can actually decode.
  final bytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAT0lEQVR42u3P'
      'QQkAAAgEsIttCIMZywi+hcEKLNXzWgQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE'
      'BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQELgvWNcGlSbHPawAAAABJRU5ErkJg'
      'gg==',
    ),
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // The grid underneath keeps a hint animating, so nothing ever settles;
  // long enough for a route or page transition to finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the viewer counts the whole library and pages past the first '
      '50', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final pages = <int>[];
    final controller = PhotosController(
      isWeb: true,
      listCache: PhotosListCache(),
      albumsCache: AlbumsCache(),
      activeHost: () => 'https://quark.local',
      getPhotos:
          ({
            int offset = 0,
            int limit = 50,
            String? serial,
            PhotoSortField sort = PhotoSortField.added,
            PhotoSortOrder order = PhotoSortOrder.desc,
          }) async {
            pages.add(offset);
            final end = (offset + limit).clamp(0, 364);
            return wire.PaginatedPhotosResponse(
              photos: [
                for (var i = offset; i < end; i++)
                  wire.PhotoItem(
                    relPath: 'camera/$i.jpg',
                    fileName: '$i.jpg',
                    size: 1,
                    mtime: 0,
                    serial: 'sd1',
                  ),
              ],
              total: 364,
              offset: offset,
              limit: limit,
            );
          },
      listFavoriteKeys: () async => {},
      listAlbums: ({bool tree = false}) async => [],
      downloadFileBytes: (path, {String? serial, String? fileName}) async =>
          bytes,
      // A bundled sample for every tile, so the grid makes no request.
      thumbnailUrl: (path, {String? serial, String? size}) => Uri(
        scheme: DemoPhotosService.assetScheme,
        path: '${DemoPhotosService.assetDir}/aurora.jpg',
      ),
      searchFiles: null,
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: PhotosPage(controller: controller)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(pages, [0]);
    expect(controller.photoCount, 50);

    await tester.tap(find.byKey(const ValueKey('photo_tile_sd1:camera/0.jpg')));
    // Past the double-tap window, so the tap lands as one.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);
    expect(find.byType(ImageViewerPage), findsOneWidget);
    expect(find.text('1 / 364'), findsOneWidget);

    // Step to photo 51, past the 50 the grid had loaded.
    for (var i = 0; i < 50; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await settle(tester);
    }

    expect(find.text('51 / 364'), findsOneWidget);
    expect(pages, [0, 50]);
    expect(controller.photoCount, 100);
  });
}
