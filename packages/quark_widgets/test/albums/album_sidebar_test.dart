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

void main() {
  AlbumSidebar sidebar({
    List<AlbumItem> albums = _albums,
    bool isLoading = false,
    String? error,
    bool shrinkWrap = false,
    List<String>? events,
  }) {
    void record(String e) => events?.add(e);
    return AlbumSidebar(
      albums: albums,
      isLoading: isLoading,
      error: error,
      shrinkWrap: shrinkWrap,
      expandedIds: const {2},
      onAlbumSelected: (a) => record('select:${a.id}'),
      onToggleExpanded: (id) => record('toggle:$id'),
      onCreateAlbum: () => record('create'),
      onAlbumLongPress: (a) => record('long:${a.id}'),
    );
  }

  Widget bounded(Widget child) => Row(
    children: [
      SizedBox(width: 280, child: child),
      const Expanded(child: SizedBox()),
    ],
  );

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

    expect(events, ['create', 'select:2', 'toggle:2', 'long:3']);
  });

  testBothViewports('shrink-wraps under unbounded height (#1599)', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      CustomScrollView(
        slivers: [SliverToBoxAdapter(child: sidebar(shrinkWrap: true))],
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Trips'), findsOneWidget);
  });

  testBothViewports('gives system albums their glyph and no long press', (
    tester,
    size,
  ) async {
    await pumpAt(tester, bounded(sidebar()), size: size);

    expect(find.byIcon(QuarkIcons.star_rounded), findsOneWidget);
    final tiles = tester.widgetList<AlbumTreeTile>(find.byType(AlbumTreeTile));
    expect(tiles.firstWhere((t) => t.album.id == 1).onLongPress, isNull);
    expect(tiles.firstWhere((t) => t.album.id == 2).onLongPress, isNotNull);
  });

  testBothViewports('shows a progress bar while loading', (tester, size) async {
    await pumpAt(tester, bounded(sidebar(isLoading: true)), size: size);

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Trips'), findsNothing);
  });

  testBothViewports('says so when there are no albums', (tester, size) async {
    await pumpAt(tester, bounded(sidebar(albums: const [])), size: size);

    expect(find.text('No albums yet'), findsOneWidget);
  });

  testBothViewports('shows the error', (tester, size) async {
    await pumpAt(
      tester,
      bounded(sidebar(error: "Couldn't load your albums.")),
      size: size,
    );

    expect(find.text("Couldn't load your albums."), findsOneWidget);
  });
}
