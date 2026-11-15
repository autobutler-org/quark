import 'package:material_ui/material_ui.dart';
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

/// #3112: the Albums header folds the whole list away, and the page keeps
/// what was showing. A phone shows the list in the Library picker rather than
/// above the grid (#4149), so the scroll no longer moves with it.
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

  /// Pumps the page at [size] on [platform].
  Future<void> pumpSidebar(
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
  }

  testWidgets('folding and reopening keeps the album, its branches, the '
      'sort and the grid, through a refresh', (tester) async {
    final controller = sampleLibrary();
    await pumpSidebar(tester, controller, size: desktop);
    await tester.tap(home);
    await settle(tester);
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
