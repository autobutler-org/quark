import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/albums_cache.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/controllers/photos_list_cache.dart';
import 'package:quark/models/paginated_photos_response.dart' as wire;
import 'package:quark/models/photo_album.dart';
import 'package:quark/models/photo_sort.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_thumbnail_store.dart';
import '../support/tap_target_guidelines.dart' show setViewport;

/// A Quark with three photos and one album, "Trips", whose count is the
/// number of photos in it, as the Quark counts.
class _FakeQuark {
  final Map<int, List<String>> albumFiles = {
    1: ['camera/0.jpg'],
  };

  PhotoAlbum _trips() => PhotoAlbum(
    id: 1,
    name: 'Trips',
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
    itemCount: albumFiles[1]!.length,
  );

  PhotosController controller(Uint8List bytes) => PhotosController(
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
          String? q,
        }) async => wire.PaginatedPhotosResponse(
          photos: [
            for (var i = 0; i < 3; i++)
              wire.PhotoItem(
                relPath: 'camera/$i.jpg',
                fileName: '$i.jpg',
                size: 1,
                mtime: 0,
                serial: 'sd1',
              ),
          ],
          total: 3,
          offset: 0,
          limit: limit,
        ),
    listFavoriteKeys: () async => {},
    listAlbums: ({bool tree = false}) async => [_trips()],
    listAlbumItems:
        (
          albumId, {
          PhotoSortField sort = PhotoSortField.added,
          PhotoSortOrder order = PhotoSortOrder.desc,
        }) async => [
          for (final (i, path) in (albumFiles[albumId] ?? const []).indexed)
            PhotoAlbumItem(
              id: i,
              albumId: albumId,
              deviceSerial: 'sd1',
              relPath: path,
              addedAt: DateTime(2024),
            ),
        ],
    addPhotoToAlbum:
        (albumId, {required deviceSerial, required relPath}) async {
          final files = albumFiles.putIfAbsent(albumId, () => []);
          if (files.contains(relPath)) return false;
          files.add(relPath);
          return true;
        },
    downloadFileBytes: (path, {String? serial, String? fileName}) async =>
        bytes,
    thumbnailUrl: (path, {String? serial, String? size}) =>
        Uri.parse('https://quark.local/api/v0/thumbnails/$serial/$path'),
    searchFiles: null,
  );
}

/// #3361: re-adding a photo an album already holds said it was added, the
/// photos an album already held could be picked again, the sidebar's count
/// stayed stale after an add, and a one-photo album's tile went grey after
/// the viewer closed.
void main() {
  // 64x64 solid PNG, which both the thumbnail and the viewer can decode.
  final png = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAT0lEQVR42u3P'
      'QQkAAAgEsIttCIMZywi+hcEKLNXzWgQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE'
      'BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQELgvWNcGlSbHPawAAAABJRU5ErkJg'
      'gg==',
    ),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ThumbnailCacheManager.instance = FakeThumbnailStore.of(png);
  });

  tearDown(() {
    imageCache
      ..clear()
      ..clearLiveImages();
  });

  // The grid keeps a hint animating, so nothing ever settles; long enough
  // for a sheet, route or snack bar to finish arriving, with real time for
  // the thumbnails' file reads.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<PhotosController> pumpPage(
    WidgetTester tester,
    _FakeQuark quark, {
    String location = AppRoutes.photos,
  }) async {
    setViewport(tester, const Size(1280, 800));

    final controller = quark.controller(png);
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: AppRoutes.photos,
          builder: (context, state) => PhotosPage(
            album: state.uri.queryParameters[AppRoutes.photosAlbumParam],
            controller: controller,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await settle(tester);
    return controller;
  }

  Finder tile(String relPath) =>
      find.byKey(ValueKey('photo_tile_sd1:$relPath'));

  bool? selected(WidgetTester tester, String relPath) => tester
      .getSemantics(tile(relPath))
      .flagsCollection
      .isSelected
      .toBoolOrNull();

  Finder albumCount(String count) => find.descendant(
    of: find.byKey(const ValueKey('album_tile_1')),
    matching: find.text(count),
  );

  testWidgets('a photo already in the album says so, not "1 photo added"', (
    tester,
  ) async {
    final quark = _FakeQuark();
    await pumpPage(tester, quark);

    await tester.longPress(tile('camera/0.jpg'));
    await settle(tester);
    await tester.tap(
      find.byKey(const ValueKey('photo_selection_add_to_album')),
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('album_picker_1')));
    await settle(tester);

    expect(find.text('Already in "Trips"'), findsOneWidget);
    expect(find.textContaining('added to'), findsNothing);
    expect(quark.albumFiles[1], ['camera/0.jpg']);
    expect(albumCount('1'), findsOneWidget);
  });

  testWidgets('adding photos to an album shows its own checked, and they '
      'cannot be picked', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpPage(tester, _FakeQuark(), location: '/photos?album=1');

    await tester.tap(find.byKey(const ValueKey('photos_add_to_album')));
    await settle(tester);

    expect(tile('camera/1.jpg'), findsOneWidget, reason: 'the library shows');
    expect(selected(tester, 'camera/0.jpg'), isTrue);
    expect(selected(tester, 'camera/1.jpg'), isFalse);

    await tester.tap(tile('camera/0.jpg'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(selected(tester, 'camera/0.jpg'), isTrue);
    expect(find.text('Done (0)'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a real add moves the sidebar count without a reload', (
    tester,
  ) async {
    final quark = _FakeQuark();
    final controller = await pumpPage(
      tester,
      quark,
      location: '/photos?album=1',
    );
    expect(albumCount('1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('photos_add_to_album')));
    await settle(tester);
    await tester.tap(tile('camera/1.jpg'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('photos_selection_done')));
    await settle(tester);

    expect(find.text('1 photo added to "Trips"'), findsOneWidget);
    expect(controller.selectedAlbumId, 1);
    expect(controller.photoCount, 2);
    expect(albumCount('2'), findsOneWidget);
  });

  testWidgets('a one-photo album repaints its tile after the viewer closes', (
    tester,
  ) async {
    await pumpPage(tester, _FakeQuark(), location: '/photos?album=1');

    ui.Image? shown() {
      final raw = find.descendant(
        of: tile('camera/0.jpg'),
        matching: find.byType(RawImage),
      );
      return raw.evaluate().isEmpty ? null : tester.widget<RawImage>(raw).image;
    }

    final before = shown();
    expect(before, isNotNull, reason: 'the tile paints no picture');

    await tester.tap(tile('camera/0.jpg'));
    // Past the double-tap window, so the tap lands as one.
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(find.byType(ImageViewerPage), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byType(ImageViewerPage), findsNothing);

    final after = shown();
    expect(after, isNotNull, reason: 'the tile paints no picture');
    expect(after!.debugDisposed, isFalse);
    // Each listener holds its own clone of a frame; a clone of the same one
    // is the same decode (#3366).
    expect(after.isCloneOf(before!), isTrue, reason: 'decoded a second time');
    expect(tester.takeException(), isNull);
  });
}
