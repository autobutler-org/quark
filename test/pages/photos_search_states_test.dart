import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/albums_cache.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/controllers/photos_list_cache.dart';
import 'package:quark/models/paginated_photos_response.dart' as wire;
import 'package:quark/models/photo_sort.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/demo_photos_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/tap_target_guidelines.dart';

/// #3524: the Photos page's search states, at a phone and a desktop width.
/// An empty library stays the empty library, a query the Quark answers with
/// nothing says so, a search the Quark cannot answer says why and a refresh
/// tries it again, and typing a name narrows the grid until the query is
/// cleared.
void main() {
  const beach = 'beach.jpg';
  const mountain = 'mountain.jpg';
  final searchError = Errors.message(
    const ApiException(500),
    'search your photos',
  );

  Finder tile(String name) =>
      find.byKey(ValueKey('photo_tile_sd1:camera/$name'));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// The refresh guard reads the wall clock, which the test clock does not
  /// move, so a retry tapped in the same second as the load is ignored.
  Future<void> outwaitRefreshDebounce(WidgetTester tester) {
    return tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
  }

  Future<void> pumpPhotos(
    WidgetTester tester,
    PhotosController controller,
    Size size,
  ) async {
    setViewport(tester, size);

    final router = GoRouter(
      initialLocation: AppRoutes.photos,
      routes: [
        GoRoute(
          path: AppRoutes.photos,
          builder: (context, state) => PhotosPage(controller: controller),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await settle(tester);
  }

  Future<void> openSearch(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('photos_search')));
    await tester.pump();
    await tester.pump();
  }

  Future<void> typeQuery(WidgetTester tester, String query) async {
    await tester.enterText(
      find.byKey(const ValueKey('photos_search_field')),
      query,
    );
    await settle(tester);
  }

  for (final (name, size) in [
    ('phone', narrowViewport),
    ('desktop', wideViewport),
  ]) {
    testWidgets('a $name empty library stays empty when search is open', (
      tester,
    ) async {
      final library = _Library(const []);
      await pumpPhotos(tester, library.controller(), size);
      await openSearch(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('photos_search_field')), findsOneWidget);
      expect(find.text('No photos yet'), findsOneWidget);
      expect(
        find.text('Photos you upload to Quark will appear here.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('photos_empty_upload')), findsOneWidget);
      expect(find.textContaining('No photos match'), findsNothing);
      expect(find.text(searchError), findsNothing);
      expect(find.byType(PhotoGridTile), findsNothing);
      expect(library.queries, isEmpty);
    });

    testWidgets('a $name search with no matches says so', (tester) async {
      final library = _Library(const [beach, mountain]);
      await pumpPhotos(tester, library.controller(), size);
      expect(tile(beach), findsOneWidget);
      expect(tile(mountain), findsOneWidget);

      await openSearch(tester);
      await typeQuery(tester, 'zzz');

      expect(tester.takeException(), isNull);
      expect(find.text('No photos match "zzz"'), findsOneWidget);
      expect(find.text('Search looks at file names.'), findsOneWidget);
      expect(find.text('No photos yet'), findsNothing);
      expect(find.text(searchError), findsNothing);
      expect(find.byType(PhotoGridTile), findsNothing);
      expect(library.queries, ['zzz']);
    });

    testWidgets('a $name failed search says why and refresh retries it', (
      tester,
    ) async {
      final library = _Library(const [beach, mountain])
        ..searchError = const ApiException(500);
      await pumpPhotos(tester, library.controller(), size);
      expect(tile(beach), findsOneWidget);

      await openSearch(tester);
      await typeQuery(tester, 'beach');

      // The loaded page has a match, and the error still replaces it: a
      // failed search must not look like "nothing matches" or like the
      // page that was already on screen.
      expect(tester.takeException(), isNull);
      expect(find.text(searchError), findsOneWidget);
      expect(find.textContaining('ApiException'), findsNothing);
      expect(find.textContaining('No photos match'), findsNothing);
      expect(find.text('No photos yet'), findsNothing);
      expect(find.byType(PhotoGridTile), findsNothing);
      expect(library.queries, ['beach']);

      library.searchError = null;
      await outwaitRefreshDebounce(tester);
      await tester.tap(find.byKey(const ValueKey('refresh_button')));
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(searchError), findsNothing);
      expect(tile(beach), findsOneWidget);
      expect(tile(mountain), findsNothing);
      expect(library.queries, ['beach', 'beach']);
    });

    testWidgets('a $name search narrows as you type and returns when cleared', (
      tester,
    ) async {
      final library = _Library(const [beach, mountain]);
      await pumpPhotos(tester, library.controller(), size);
      await openSearch(tester);
      await typeQuery(tester, 'BEACH');

      expect(tester.takeException(), isNull);
      expect(tile(beach), findsOneWidget);
      expect(tile(mountain), findsNothing);
      expect(
        find.byKey(const ValueKey('photo_tile_sd1:docs/notes.txt')),
        findsNothing,
      );
      expect(find.textContaining('No photos match'), findsNothing);
      expect(_fieldText(tester), 'BEACH');

      await typeQuery(tester, '');

      expect(tester.takeException(), isNull);
      expect(_fieldText(tester), isEmpty);
      expect(find.byKey(const ValueKey('photos_search_field')), findsOneWidget);
      expect(tile(beach), findsOneWidget);
      expect(tile(mountain), findsOneWidget);
      expect(find.textContaining('No photos match'), findsNothing);
      expect(find.text('No photos yet'), findsNothing);
    });
  }

  testWidgets('a search of 600 matches scrolls past 500 (#3523)', (
    tester,
  ) async {
    final library = _Library([for (var i = 0; i < 600; i++) 'shot-$i.jpg']);
    final controller = library.controller();
    await pumpPhotos(tester, controller, narrowViewport);
    await openSearch(tester);
    await typeQuery(tester, 'shot');

    List<int> asked() => [
      for (final page in library.pages)
        if (page.q == 'shot') page.offset,
    ];

    // The first page is painted before the rest is asked for.
    expect(asked().first, 0);
    expect(asked(), isNot(contains(500)));
    expect(controller.photos, hasLength(PhotosController.pageSize));
    expect(controller.hasMore, isTrue);
    expect(controller.photoTotal, 600);
    expect(
      find.byKey(const ValueKey('photo_tile_sd1:camera/shot-0.jpg')),
      findsWidgets,
    );

    final position = tester
        .state<ScrollableState>(
          find
              .ancestor(
                of: find.byType(PhotoGridTile).first,
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    for (var n = 0; n < 40 && !asked().contains(500); n++) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      await settle(tester);
    }

    expect(asked(), contains(50));
    expect(asked(), contains(500));
    expect(controller.photos.length, greaterThan(500));
    expect(tester.takeException(), isNull);
  });
}

String _fieldText(WidgetTester tester) {
  return tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('photos_search_field')),
          matching: find.byType(EditableText),
        ),
      )
      .controller
      .text;
}

/// A Quark library of [names]. Search asks getPhotos with `q` and pages the
/// matches; each page's total is the match count (#3523).
class _Library {
  _Library(this.names);

  final List<String> names;

  /// What a search throws instead of answering, when set.
  Object? searchError;

  /// Every non-blank query the page asked the Quark, in order.
  final List<String> queries = [];

  /// Every getPhotos page, with the query it carried. Null is the library.
  final List<({int offset, String? q})> pages = [];

  PhotosController controller() => PhotosController(
    isWeb: true,
    listCache: PhotosListCache(scope: () => 'photos-search-states'),
    albumsCache: AlbumsCache(scope: () => 'photos-search-states'),
    activeHost: () => 'https://quark.local',
    searchDelay: Duration.zero,
    getPhotos:
        ({
          int offset = 0,
          int limit = 50,
          String? serial,
          PhotoSortField sort = PhotoSortField.added,
          PhotoSortOrder order = PhotoSortOrder.desc,
          String? q,
        }) async {
          final query = q?.trim() ?? '';
          pages.add((offset: offset, q: query.isEmpty ? null : query));
          if (query.isNotEmpty) {
            queries.add(query);
            final error = searchError;
            if (error != null) throw error;
          }
          final matched = [
            for (final name in names)
              if (query.isEmpty ||
                  name.toLowerCase().contains(query.toLowerCase()))
                name,
          ];
          final start = offset.clamp(0, matched.length);
          final end = (start + limit).clamp(start, matched.length);
          return wire.PaginatedPhotosResponse(
            photos: [
              for (final name in matched.sublist(start, end))
                wire.PhotoItem(
                  relPath: 'camera/$name',
                  fileName: name,
                  size: 1,
                  mtime: 1,
                  serial: 'sd1',
                ),
            ],
            total: matched.length,
            offset: start,
            limit: limit,
          );
        },
    listFavoriteKeys: () async => {},
    listAlbums: ({bool tree = false}) async => [],
    thumbnailUrl: (path, {String? serial, String? size}) => Uri(
      scheme: DemoPhotosService.assetScheme,
      path: '${DemoPhotosService.assetDir}/aurora.jpg',
    ),
  );
}
