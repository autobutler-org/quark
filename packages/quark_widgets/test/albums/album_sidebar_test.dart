import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _albums = [
  AlbumItem(id: 1, name: 'Favorites', isSystem: true, isFavorites: true),
  AlbumItem(
    id: 2,
    name: 'Trips',
    itemCount: 3,
    children: [AlbumItem(id: 3, name: 'Iceland', parentId: 2)],
  ),
];

const _allPhotos = ValueKey('album_sidebar_all_photos');

void main() {
  AlbumSidebar sidebar({
    List<AlbumItem> albums = _albums,
    bool isLoading = false,
    String? error,
    bool shrinkWrap = false,
    int? selectedAlbumId,
    bool withAllPhotos = false,
    List<String>? events,
  }) {
    void record(String e) => events?.add(e);
    return AlbumSidebar(
      albums: albums,
      isLoading: isLoading,
      error: error,
      shrinkWrap: shrinkWrap,
      selectedAlbumId: selectedAlbumId,
      expandedIds: const {2},
      onAlbumSelected: (a) => record('select:${a.id}'),
      onToggleExpanded: (id) => record('toggle:$id'),
      onCreateAlbum: () => record('create'),
      onAlbumMenu: (a) => record('menu:${a.id}'),
      onAllPhotosSelected: withAllPhotos ? () => record('all') : null,
    );
  }

  Widget bounded(Widget child) => Row(
    children: [
      SizedBox(width: 280, child: child),
      const Expanded(child: SizedBox()),
    ],
  );

  /// The primary tint on the row's background, or null when unselected.
  Color? rowTint(WidgetTester tester, Finder row) {
    final box = tester.widget<Container>(
      find.descendant(of: row, matching: find.byType(Container)).first,
    );
    final color = (box.decoration! as BoxDecoration).color;
    return color == Colors.transparent ? null : color;
  }

  FontWeight? labelWeight(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label)).style?.fontWeight;

  testBothViewports('fills a bounded parent and emits every action', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(tester, bounded(sidebar(events: events)), size: size);

    expect(tester.takeException(), isNull);
    expect(find.text('Iceland'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('album_create')));
    await tester.tap(find.byKey(const ValueKey('album_tile_2')));
    await tester.tap(find.byKey(const ValueKey('album_expand_2')));
    await tester.longPress(find.byKey(const ValueKey('album_tile_3')));
    await tester.pump();

    expect(events, ['create', 'select:2', 'toggle:2', 'menu:3']);
  });

  testBothViewports('shrink-wraps under unbounded height (#1599)', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: sidebar(shrinkWrap: true, withAllPhotos: true),
          ),
        ],
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('All photos'), findsOneWidget);
    expect(find.text('Trips'), findsOneWidget);
  });

  testBothViewports('gives system albums their glyph and no menu', (
    tester,
    size,
  ) async {
    await pumpAt(tester, bounded(sidebar()), size: size);

    expect(find.byIcon(QuarkIcons.star_rounded), findsOneWidget);
    final tiles = tester.widgetList<AlbumTreeTile>(find.byType(AlbumTreeTile));
    expect(tiles.firstWhere((t) => t.album.id == 1).onMenu, isNull);
    expect(tiles.firstWhere((t) => t.album.id == 2).onMenu, isNotNull);
    expect(find.byKey(const ValueKey('album_menu_1')), findsNothing);
    expect(find.byKey(const ValueKey('album_menu_2')), findsOneWidget);
  });

  testBothViewports('opens a user album menu from its button', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(tester, bounded(sidebar(events: events)), size: size);

    await tester.tap(find.byKey(const ValueKey('album_menu_2')));
    await tester.pump();

    expect(events, ['menu:2']);
  });

  testBothViewports('shows a progress bar while loading', (tester, size) async {
    await pumpAt(
      tester,
      bounded(sidebar(isLoading: true, withAllPhotos: true)),
      size: size,
    );

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Trips'), findsNothing);
    expect(find.byKey(_allPhotos), findsOneWidget);
  });

  testBothViewports('says so when there are no albums', (tester, size) async {
    await pumpAt(
      tester,
      bounded(sidebar(albums: const [], withAllPhotos: true)),
      size: size,
    );

    expect(find.text('No albums yet'), findsOneWidget);
    expect(find.byKey(_allPhotos), findsOneWidget);
  });

  testBothViewports('shows the error', (tester, size) async {
    await pumpAt(
      tester,
      bounded(
        sidebar(error: "Couldn't load your albums.", withAllPhotos: true),
      ),
      size: size,
    );

    expect(find.text("Couldn't load your albums."), findsOneWidget);
    expect(find.byKey(_allPhotos), findsOneWidget);
  });

  testBothViewports('leaves out All photos without its callback', (
    tester,
    size,
  ) async {
    await pumpAt(tester, bounded(sidebar()), size: size);

    expect(find.byKey(_allPhotos), findsNothing);
    expect(find.text('All photos'), findsNothing);
  });

  testBothViewports('puts All photos first and reports a tap', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      bounded(sidebar(withAllPhotos: true, events: events)),
      size: size,
    );

    expect(tester.takeException(), isNull);
    final allPhotosY = tester.getTopLeft(find.byKey(_allPhotos)).dy;
    expect(
      allPhotosY,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('album_tile_1'))).dy,
      ),
    );
    expect(find.byIcon(QuarkIcons.photo_library_outlined), findsOneWidget);

    expect(tester.widget<InkWell>(find.byKey(_allPhotos)).onLongPress, isNull);

    await tester.tap(find.byKey(_allPhotos));
    await tester.pump();

    expect(events, ['all']);
  });

  testBothViewports('highlights All photos when no album is selected', (
    tester,
    size,
  ) async {
    await pumpAt(tester, bounded(sidebar(withAllPhotos: true)), size: size);

    final allPhotosTint = rowTint(tester, find.byKey(_allPhotos));
    expect(allPhotosTint, isNotNull);
    expect(labelWeight(tester, 'All photos'), FontWeight.w600);
    expect(rowTint(tester, find.byKey(const ValueKey('album_tile_2'))), isNull);

    // Same highlight as a selected album, not merely some highlight.
    await pumpAt(
      tester,
      bounded(sidebar(withAllPhotos: true, selectedAlbumId: 2)),
      size: size,
    );
    expect(
      rowTint(tester, find.byKey(const ValueKey('album_tile_2'))),
      allPhotosTint,
    );
  });

  testBothViewports('highlights the selected album instead', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      bounded(sidebar(withAllPhotos: true, selectedAlbumId: 2)),
      size: size,
    );

    expect(rowTint(tester, find.byKey(_allPhotos)), isNull);
    expect(labelWeight(tester, 'All photos'), FontWeight.normal);
    expect(
      rowTint(tester, find.byKey(const ValueKey('album_tile_2'))),
      isNotNull,
    );
    expect(labelWeight(tester, 'Trips'), FontWeight.w600);
  });
}
