import 'dart:async';

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

/// #3111: on a phone, picking an album scrolls the grid into view once, to a
/// position the new layout can hold. Every case here watches the scroll
/// position frame by frame: the defect was a scroll past the end that sprang
/// back, which is over by the time the page settles.
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

  // A phone tall enough to show every album row with the sidebar scrolled
  // into view, and short enough that a two-photo album cannot scroll the
  // whole sidebar away again.
  const phone = Size(390, 600);
  final home = find.byKey(
    ValueKey('album_tile_${DemoPhotosService.homeAlbumId}'),
  );
  final summerTrip = find.byKey(
    ValueKey('album_tile_${DemoPhotosService.summerTripAlbumId}'),
  );
  const frame = Duration(milliseconds: 16);

  /// Demo mode's sample library, with each album load held until the test
  /// completes its entry in [loads] when one is given.
  PhotosController sampleLibrary({
    List<Completer<void>>? loads,
  }) => PhotosController(
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
        (id, {sort = PhotoSortField.taken, order = PhotoSortOrder.desc}) async {
          if (loads != null) {
            final load = Completer<void>();
            loads.add(load);
            await load.future;
          }
          return DemoPhotosService.listAlbumItems(id, sort: sort, order: order);
        },
    searchFiles: null,
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(frame);
    }
  }

  /// Pumps the page on [platform], whose scroll physics decide whether a
  /// scroll may pass the end, scrolled to the top so the sidebar shows, and
  /// returns its scroll position.
  Future<ScrollPosition> pumpAtSidebar(
    WidgetTester tester,
    PhotosController controller, {
    TargetPlatform platform = TargetPlatform.iOS,
    Size size = phone,
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

  /// Pumps [frames] frames and returns where each left the scroll, failing
  /// on one that left it outside what the layout can hold unless [bounded]
  /// is off.
  Future<List<double>> watch(
    WidgetTester tester,
    ScrollPosition position, {
    int frames = 40,
    bool bounded = true,
  }) async {
    final seen = <double>[];
    for (var i = 0; i < frames; i++) {
      await tester.pump(frame);
      seen.add(position.pixels);
      if (!bounded) continue;
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

  /// How far the scroll has to go to put the grid at the top of the viewport.
  double sidebarHeight(WidgetTester tester) =>
      tester.getSize(find.byKey(const ValueKey('split_view_sidebar'))).height +
      QuarkSplitView.dividerWidth;

  void expectOneWayTo(List<double> seen, double target) {
    expect(seen, [...seen]..sort(), reason: 'the scroll reversed');
    expect(seen.last, moreOrLessEquals(target, epsilon: 0.01));
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('a short album scrolls once to the end of its content '
        '($platform)', (tester) async {
      final position = await pumpAtSidebar(
        tester,
        sampleLibrary(),
        platform: platform,
      );

      await tester.tap(home);
      final seen = await watch(tester, position);

      expect(
        position.maxScrollExtent,
        inExclusiveRange(0, sidebarHeight(tester)),
        reason: 'the album is too short to scroll the sidebar away',
      );
      expectOneWayTo(seen, position.maxScrollExtent);
    });
  }

  testWidgets('a long view still scrolls the sidebar away', (tester) async {
    final position = await pumpAtSidebar(tester, sampleLibrary());
    // Measured now: scrolled away, the sidebar is no longer built.
    final target = sidebarHeight(tester);
    await tester.tap(home);
    await watch(tester, position);
    position.jumpTo(0);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('album_sidebar_all_photos')));
    final seen = await watch(tester, position);

    expectOneWayTo(seen, target);
  });

  testWidgets('an album kept from an earlier visit scrolls once', (
    tester,
  ) async {
    final position = await pumpAtSidebar(tester, sampleLibrary());
    await tester.tap(home);
    await watch(tester, position);
    position.jumpTo(0);
    await tester.pump();
    await tester.tap(summerTrip);
    await watch(tester, position);
    position.jumpTo(0);
    await tester.pump();

    await tester.tap(home);
    final seen = await watch(tester, position);

    expectOneWayTo(seen, position.maxScrollExtent);
  });

  testWidgets('the scroll waits for a slow album to load', (tester) async {
    final loads = <Completer<void>>[];
    final position = await pumpAtSidebar(tester, sampleLibrary(loads: loads));

    await tester.tap(home);
    final waiting = await watch(tester, position);
    expect(waiting, everyElement(0), reason: 'the content is not there yet');

    loads.single.complete();
    final seen = await watch(tester, position);

    expect(seen.last, greaterThan(0));
    expectOneWayTo(seen, position.maxScrollExtent);
  });

  testWidgets('a second pick takes over from the first', (tester) async {
    final position = await pumpAtSidebar(tester, sampleLibrary());

    await tester.tap(summerTrip);
    final first = await watch(tester, position, frames: 6);
    expect(first.last, greaterThan(0), reason: 'the first scroll is under way');
    // A touch on a moving list only stops it, so this pick arrives the way a
    // keyboard's does.
    tester.widget<InkWell>(home).onTap!();
    // Home ends above where the first scroll had reached, so the way back is
    // the one stretch outside the content.
    final seen = await watch(tester, position, bounded: false);

    expect(
      seen,
      everyElement(lessThanOrEqualTo(first.last)),
      reason: 'the first scroll carried on',
    );
    expect(
      seen.last,
      moreOrLessEquals(position.maxScrollExtent, epsilon: 0.01),
    );
    expect(position.maxScrollExtent, lessThan(first.last));
  });

  testWidgets('a pick replaced while it loads never scrolls', (tester) async {
    final loads = <Completer<void>>[];
    final position = await pumpAtSidebar(tester, sampleLibrary(loads: loads));

    await tester.tap(summerTrip);
    await watch(tester, position, frames: 3);
    await tester.tap(home);
    await watch(tester, position, frames: 3);
    loads.first.complete();
    final stale = await watch(tester, position);
    expect(stale, everyElement(0), reason: 'Summer Trip is no longer showing');

    loads.last.complete();
    final seen = await watch(tester, position);

    expect(seen.last, greaterThan(0));
    expectOneWayTo(seen, position.maxScrollExtent);
  });

  testWidgets('reduced motion jumps straight to a position that holds', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final position = await pumpAtSidebar(tester, sampleLibrary());

    await tester.tap(home);
    final seen = await watch(tester, position);

    expect(seen.last, greaterThan(0));
    expect(seen.toSet(), {
      0,
      position.maxScrollExtent,
    }, reason: 'a jump has no frames in between');
  });

  testWidgets('the wide layout leaves the grid where it is', (tester) async {
    final position = await pumpAtSidebar(
      tester,
      sampleLibrary(),
      size: const Size(1280, 800),
    );

    await tester.tap(home);
    final seen = await watch(tester, position);

    expect(seen, everyElement(0));
  });
}
