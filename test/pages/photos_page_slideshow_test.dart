import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/albums_cache.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/controllers/photos_list_cache.dart';
import 'package:quark/models/paginated_photos_response.dart' as wire;
import 'package:quark/models/photo_album.dart';
import 'package:quark/models/photo_sort.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/pages/slideshow_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_thumbnail_store.dart';
import '../support/tap_target_guidelines.dart' show setViewport;

/// A Quark with four photos, one of them a video, and one album, "Trips",
/// holding three of them.
PhotosController _controller(Uint8List bytes) => PhotosController(
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
          for (final name in ['0.jpg', '1.jpg', '2.jpg', '3.mp4'])
            wire.PhotoItem(
              relPath: 'camera/$name',
              fileName: name,
              size: 1,
              mtime: 0,
              serial: 'sd1',
            ),
        ],
        total: 4,
        offset: 0,
        limit: limit,
      ),
  listFavoriteKeys: () async => {},
  listAlbums: ({bool tree = false}) async => [
    PhotoAlbum(
      id: 1,
      name: 'Trips',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
      itemCount: 3,
    ),
  ],
  listAlbumItems:
      (
        albumId, {
        PhotoSortField sort = PhotoSortField.added,
        PhotoSortOrder order = PhotoSortOrder.desc,
      }) async => [
        for (final (i, path) in [
          'camera/2.jpg',
          'camera/3.mp4',
          'camera/0.jpg',
        ].indexed)
          PhotoAlbumItem(
            id: i,
            albumId: albumId,
            deviceSerial: 'sd1',
            relPath: path,
            addedAt: DateTime(2024),
          ),
      ],
  downloadFileBytes: (path, {String? serial, String? fileName}) async => bytes,
  thumbnailUrl: (path, {String? serial, String? size}) =>
      Uri.parse('https://quark.local/api/v0/thumbnails/$serial/$path'),
  searchFiles: null,
);

/// #4179: an album and a selection each play as a slideshow, in the grid's
/// order.
void main() {
  // 64x64 solid PNG, which the thumbnails can decode.
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

  // The grid keeps a hint animating, so nothing ever settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<PhotosController> pumpPage(
    WidgetTester tester, {
    String location = AppRoutes.photos,
    Size size = const Size(1280, 800),
  }) async {
    setViewport(tester, size);
    final controller = _controller(png);
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

  /// The photos the open slideshow plays, by id.
  List<String> playing(WidgetTester tester) => [
    for (final photo
        in tester
            .widget<SlideshowPage>(find.byType(SlideshowPage))
            .controller
            .photos)
      photo.id,
  ];

  Future<void> closeSlideshow(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byType(SlideshowPage), findsNothing);
  }

  testWidgets('Slideshow in an album plays its photos in the grid order', (
    tester,
  ) async {
    final controller = await pumpPage(tester, location: '/photos?album=1');
    final grid = [for (final photo in controller.photos) photo.id];
    expect(grid, hasLength(3));

    await tester.tap(find.byKey(const ValueKey('photos_slideshow')));
    await settle(tester);

    expect(find.byType(SlideshowPage), findsOneWidget);
    // The video is left out.
    expect(playing(tester), [
      for (final id in grid)
        if (!id.endsWith('.mp4')) id,
    ]);

    await closeSlideshow(tester);
  });

  testWidgets('a phone plays an album from the Tools menu', (tester) async {
    final controller = await pumpPage(
      tester,
      location: '/photos?album=1',
      size: const Size(360, 640),
    );
    final grid = [for (final photo in controller.photos) photo.id];

    await tester.tap(find.byKey(const ValueKey('app_bar_bottom_menu')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('photos_menu_slideshow')));
    await settle(tester);

    expect(playing(tester), [
      for (final id in grid)
        if (!id.endsWith('.mp4')) id,
    ]);
    expect(tester.takeException(), isNull);

    await closeSlideshow(tester);
  });

  testWidgets('the library has no Slideshow in its bar', (tester) async {
    await pumpPage(tester);

    expect(find.byKey(const ValueKey('photos_slideshow')), findsNothing);
  });

  testWidgets('Slideshow on a selection plays only the selection, in the '
      'grid order', (tester) async {
    final controller = await pumpPage(tester);
    final grid = [for (final photo in controller.photos) photo.id];

    // Selected out of grid order.
    await tester.longPress(tile('camera/2.jpg'));
    await settle(tester);
    await tester.tap(tile('camera/0.jpg'));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('photo_selection_slideshow')));
    await settle(tester);

    expect(find.byType(SlideshowPage), findsOneWidget);
    expect(playing(tester), [
      for (final id in grid)
        if (id == 'sd1:camera/0.jpg' || id == 'sd1:camera/2.jpg') id,
    ]);

    await closeSlideshow(tester);
  });
}
