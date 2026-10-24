import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/albums_cache.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/controllers/photos_list_cache.dart';
import 'package:quark/models/photo_sort.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/demo_photos_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

/// #3112: the Albums header folds the whole list away. The page keeps what
/// was showing, and on a phone, where the list sits above the grid in one
/// scroll view, the scroll stays somewhere the shorter content can hold
/// without the spring back of #3111.
void main() {
  // The test platform is Android, so the page also asks photo_manager for the
  // device library; denying it lets the page settle.
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

  const phone = Size(390, 600);
  const desktop = Size(1280, 800);
  const frame = Duration(milliseconds: 16);
  const toggle = ValueKey('album_section_toggle');
  const allPhotos = ValueKey('album_sidebar_all_photos');
  final home = find.byKey(
    ValueKey('album_tile_${DemoPhotosService.homeAlbumId}'),
  );

  PhotosController sampleLibrary() => PhotosController(
    listCache: PhotosListCache(),
    albumsCache: AlbumsCache(),
    getPhotos: DemoPhotosService.getPhotos,
    activeHost: DemoPhotosService.activeHost,
    listFavoriteKeys: DemoPhotosService.listFavoriteKeys,
    toggleFavorite: DemoPhotosService.toggleFavorite,
    downloadFileBytes: DemoPhotosService.downloadFileBytes,
    thumbnailUrl: DemoPhotosService.thumbnailUrl,
    listAlbums: DemoPhotosService.listAlbums,
    listAlbumItems:
        (
          id, {
          sort = PhotoSortField.taken,
          order = PhotoSortOrder.desc,
        }) async =>
            DemoPhotosService.listAlbumItems(id, sort: sort, order: order),
    searchFiles: null,
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(frame);
    }
  }

  /// Pumps the page at [size] on [platform], scrolled to the top so the
  /// sidebar shows, and returns its scroll position.
  Future<ScrollPosition> pumpAtSidebar(
    WidgetTester tester,
    PhotosController controller, {
    required Size size,
    TargetPlatform platform = TargetPlatform.iOS,
  }) async {
    setViewport(tester, size);

    final router = GoRouter(
      initialLocation: AppRoutes.photos,
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
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        theme: ThemeData(platform: platform),
      ),
    );
    await settle(tester);

    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(PhotosPage),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    position.jumpTo(0);
    await tester.pump();
    return position;
  }

  /// Pumps 40 frames and returns where each left the scroll, failing on one
  /// that left it outside what the layout can hold.
  Future<List<double>> watch(
    WidgetTester tester,
    ScrollPosition position,
  ) async {
    final seen = <double>[];
    for (var i = 0; i < 40; i++) {
      await tester.pump(frame);
      seen.add(position.pixels);
      expect(
        position.pixels,
        inInclusiveRange(
          position.minScrollExtent - 0.01,
          position.maxScrollExtent + 0.01,
        ),
        reason: 'frame $i scrolled past the content',
      );
    }
    return seen;
  }

  for (final (label, size) in [('narrow', phone), ('wide', desktop)]) {
    testWidgets('folding and reopening keeps the album, its branches, the '
        'sort and the grid, through a refresh ($label)', (tester) async {
      final controller = sampleLibrary();
      final position = await pumpAtSidebar(tester, controller, size: size);
      await tester.tap(home);
      await settle(tester);
      position.jumpTo(0);
      await tester.pump();
      controller.toggleAlbumExpanded(DemoPhotosService.homeAlbumId);
      await controller.setAlbumSort(AlbumSort.nameDesc);
      await settle(tester);
      final albums = controller.albums.map((a) => a.id).toList();
      final photos = controller.photos.map((p) => p.id).toList();
      expect(photos, isNotEmpty);

      await tester.tap(find.byKey(toggle));
      await settle(tester);
      await tester
          .state<PhotosPageState>(find.byType(PhotosPage))
          .manualRefresh();
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(AlbumTreeTile), findsNothing);
      expect(find.byKey(allPhotos), findsNothing);
      expect(find.byKey(const ValueKey('album_sort')), findsOneWidget);
      expect(find.byKey(const ValueKey('album_create')), findsOneWidget);
      expect(controller.selectedAlbumId, DemoPhotosService.homeAlbumId);
      expect(controller.photos.map((p) => p.id), photos);

      await tester.tap(find.byKey(toggle));
      await settle(tester);

      expect(home, findsOneWidget);
      expect(find.byKey(allPhotos), findsOneWidget);
      expect(controller.selectedAlbumId, DemoPhotosService.homeAlbumId);
      expect(controller.expandedAlbumIds, {DemoPhotosService.homeAlbumId});
      expect(controller.albumSort, AlbumSort.nameDesc);
      expect(controller.albums.map((a) => a.id), albums);
      expect(controller.photos.map((p) => p.id), photos);
    });
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('folding under a short album settles the scroll at once, '
        'with no spring back ($platform)', (tester) async {
      final controller = sampleLibrary();
      final position = await pumpAtSidebar(
        tester,
        controller,
        size: phone,
        platform: platform,
      );
      // A short album leaves the scroll at the very end of its content, so
      // folding the list takes the ground from under it.
      await tester.tap(home);
      await watch(tester, position);
      final before = position.pixels;
      expect(before, moreOrLessEquals(position.maxScrollExtent, epsilon: 0.01));
      expect(before, greaterThan(0));

      controller.toggleAlbumsSectionExpanded();
      final folding = await watch(tester, position);

      expect(position.maxScrollExtent, lessThan(before));
      expect(folding.toSet(), {
        position.maxScrollExtent,
      }, reason: 'one correction, not an animation back into range');

      controller.toggleAlbumsSectionExpanded();
      final reopening = await watch(tester, position);

      expect(reopening.toSet(), {
        folding.last,
      }, reason: 'growing moves nothing');
    });
  }

  testWidgets('folding from the top of the sidebar leaves the scroll alone', (
    tester,
  ) async {
    final position = await pumpAtSidebar(tester, sampleLibrary(), size: phone);

    await tester.tap(find.byKey(toggle));
    final seen = await watch(tester, position);

    expect(seen, everyElement(0));
    expect(find.byType(AlbumTreeTile), findsNothing);
  });
}
