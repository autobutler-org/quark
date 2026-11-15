import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/albums_cache.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/controllers/photos_list_cache.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/models/photo_sort.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/demo_photos_service.dart';
import 'package:quark/widgets/photos/photos_bar_bottom.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

/// #4149: on a phone the photo grid is the first thing under the app bar.
/// The albums, categories and grid size are a tap away in the Library picker
/// and the Tools menu, rather than stacked above the grid where they pushed
/// the first photo halfway down the screen.
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

  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);
  const frame = Duration(milliseconds: 16);

  /// Demo mode's sample library with enough albums to fill a phone, the
  /// album list held until [albumsLoaded] completes when one is given.
  PhotosController library({Completer<void>? albumsLoaded}) {
    final albums = [
      ...DemoPhotosService.albums(),
      for (var i = 0; i < 20 - DemoPhotosService.albums().length; i++)
        PhotoAlbum(
          id: 100 + i,
          name: 'Album $i',
          createdAt: DateTime.utc(2025),
          updatedAt: DateTime.utc(2025),
          itemCount: 0,
        ),
    ];
    return PhotosController(
      listCache: PhotosListCache(),
      albumsCache: AlbumsCache(),
      getPhotos: DemoPhotosService.getPhotos,
      activeHost: DemoPhotosService.activeHost,
      listFavoriteKeys: DemoPhotosService.listFavoriteKeys,
      toggleFavorite: DemoPhotosService.toggleFavorite,
      downloadFileBytes: DemoPhotosService.downloadFileBytes,
      thumbnailUrl: DemoPhotosService.thumbnailUrl,
      listAlbums: ({tree = true}) async {
        await albumsLoaded?.future;
        return albums;
      },
      listAlbumItems:
          (
            id, {
            sort = PhotoSortField.taken,
            order = PhotoSortOrder.desc,
          }) async =>
              DemoPhotosService.listAlbumItems(id, sort: sort, order: order),
      searchFiles: null,
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(frame);
    }
  }

  Future<void> pumpPhotos(
    WidgetTester tester,
    PhotosController controller, {
    Size size = narrowViewport,
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
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await settle(tester);
  }

  ScrollPosition gridScroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(QuarkSplitView),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  /// The gap between the bottom of the app bar and the top of the first
  /// photo: at most the grid's first date header.
  double gapUnderBar(WidgetTester tester) {
    final barBottom = tester.getBottomLeft(find.byType(PhotosBarBottom)).dy;
    final firstTile = find
        .byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('photo_tile_') &&
              !(w.key! as ValueKey<String>).value.startsWith('photo_tile_m') &&
              !(w.key! as ValueKey<String>).value.startsWith('photo_tile_c'),
        )
        .first;
    return tester.getTopLeft(firstTile).dy - barBottom;
  }

  const maxHeaderHeight = 64.0;

  testWidgets('narrow: the grid starts under the app bar before and after '
      '20 albums load', (tester) async {
    final albumsLoaded = Completer<void>();
    final controller = library(albumsLoaded: albumsLoaded);
    await pumpPhotos(tester, controller);

    // The grid is still loading, and nothing stands above it.
    expect(find.byType(AlbumSidebar), findsNothing);
    expect(gridScroll(tester).pixels, 0);

    albumsLoaded.complete();
    await settle(tester);

    expect(controller.albums, hasLength(20));
    expect(tester.takeException(), isNull);
    expect(find.byType(AlbumSidebar), findsNothing);
    expect(gridScroll(tester).pixels, 0);
    expect(gapUnderBar(tester), inInclusiveRange(0, maxHeaderHeight));
  });

  testWidgets('narrow: the Library picker sheet shows an album', (
    tester,
  ) async {
    final controller = library();
    await pumpPhotos(tester, controller);
    final picker = find.byKey(const ValueKey('photos_library_picker'));
    expect(
      find.descendant(of: picker, matching: find.text('Library')),
      findsOneWidget,
    );

    await tester.tap(picker);
    await settle(tester);
    expect(find.byType(AlbumSidebar), findsOneWidget);
    expect(
      find.byKey(const ValueKey('album_sidebar_all_photos')),
      findsOneWidget,
    );

    final home = find.byKey(
      ValueKey('album_tile_${DemoPhotosService.homeAlbumId}'),
    );
    await tester.ensureVisible(home);
    await tester.pump();
    await tester.tap(home);
    await settle(tester);

    expect(controller.selectedAlbumId, DemoPhotosService.homeAlbumId);
    expect(find.byType(AlbumSidebar), findsNothing, reason: 'sheet closed');
    expect(
      find.descendant(of: picker, matching: find.text('Home')),
      findsOneWidget,
      reason: 'an album view shows the same chip, named for the album',
    );
    expect(gridScroll(tester).pixels, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow: Grid size sits in the Tools menu', (tester) async {
    final controller = library();
    await pumpPhotos(tester, controller);
    expect(find.byKey(const ValueKey('photo_columns_slider')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('app_bar_bottom_menu')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('photos_menu_grid_size')));
    await settle(tester);

    final before = controller.columns;
    await tester.tap(find.byKey(const ValueKey('photo_columns_less')));
    await tester.pump();
    expect(controller.columns, before - 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide: the sidebar pane stays beside the grid', (tester) async {
    await pumpPhotos(tester, library(), size: wideViewport);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('split_view_sidebar')),
        matching: find.byType(AlbumSidebar),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('photo_columns_slider')), findsOneWidget);
    expect(find.byKey(const ValueKey('photos_library_picker')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
