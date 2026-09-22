import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _tree = AlbumItem(
  id: 1,
  name: 'Trips',
  itemCount: 12,
  children: [
    AlbumItem(id: 2, name: 'Iceland', itemCount: 40),
    AlbumItem(id: 3, name: 'Japan'),
  ],
);

void main() {
  Future<void> pumpTile(
    WidgetTester tester, {
    Size size = wideViewport,
    AlbumItem album = _tree,
    int? selectedAlbumId,
    Set<int> expandedIds = const {},
    List<String>? events,
    bool withMenu = false,
    IconData? systemIcon,
  }) {
    void record(String e) => events?.add(e);
    return pumpAt(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 240,
          child: AlbumTreeTile(
            album: album,
            selectedAlbumId: selectedAlbumId,
            expandedIds: expandedIds,
            systemIcon: systemIcon,
            onSelected: (a) => record('select:${a.id}'),
            onToggleExpanded: (id) => record('toggle:$id'),
            onMenu: withMenu ? (a) => record('menu:${a.id}') : null,
          ),
        ),
      ),
      size: size,
    );
  }

  testBothViewports('shows the name and the item count', (tester, size) async {
    await pumpTile(tester, size: size);

    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('hides the count for an empty album', (tester) async {
    await pumpTile(
      tester,
      size: narrowViewport,
      album: const AlbumItem(id: 9, name: 'Empty'),
    );

    expect(find.text('0'), findsNothing);
  });

  testBothViewports('keeps children hidden until the id is expanded', (
    tester,
    size,
  ) async {
    await pumpTile(tester, size: size);

    expect(find.text('Iceland'), findsNothing);
    expect(find.byIcon(QuarkIcons.chevron_right_rounded), findsOneWidget);
  });

  testBothViewports('renders the children of an expanded album', (
    tester,
    size,
  ) async {
    await pumpTile(tester, size: size, expandedIds: const {1});

    expect(find.text('Iceland'), findsOneWidget);
    expect(find.text('Japan'), findsOneWidget);
    expect(find.byIcon(QuarkIcons.expand_more_rounded), findsOneWidget);
  });

  testBothViewports('indents each level further than the last', (
    tester,
    size,
  ) async {
    await pumpTile(tester, size: size, expandedIds: const {1});

    expect(
      tester.getRect(find.text('Iceland')).left,
      greaterThan(tester.getRect(find.text('Trips')).left),
    );
  });

  testBothViewports('reports the album that was tapped, at any depth', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpTile(tester, size: size, expandedIds: const {1}, events: events);

    await tester.tap(find.byKey(const ValueKey('album_tile_1')));
    await tester.tap(find.byKey(const ValueKey('album_tile_3')));
    await tester.pump();

    expect(events, ['select:1', 'select:3']);
  });

  testBothViewports('sends expansion out instead of keeping it', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpTile(tester, size: size, events: events);

    await tester.tap(find.byKey(const ValueKey('album_expand_1')));
    await tester.pump();

    // Nothing expanded on its own: the caller owns the set.
    expect(events, ['toggle:1']);
    expect(find.text('Iceland'), findsNothing);
  });

  testWidgets('gives a childless album no chevron to tap', (tester) async {
    await pumpTile(
      tester,
      size: narrowViewport,
      album: const AlbumItem(id: 7, name: 'Leaf'),
    );

    expect(find.byKey(const ValueKey('album_expand_7')), findsNothing);
  });

  testBothViewports('marks the selected album', (tester, size) async {
    await pumpTile(
      tester,
      size: size,
      selectedAlbumId: 2,
      expandedIds: const {1},
    );

    final selected = tester.widget<Text>(find.text('Iceland'));
    final unselected = tester.widget<Text>(find.text('Trips'));
    expect(selected.style?.fontWeight, FontWeight.w600);
    expect(unselected.style?.fontWeight, FontWeight.normal);
  });

  testBothViewports('opens the menu of the album under the finger', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpTile(
      tester,
      size: size,
      expandedIds: const {1},
      withMenu: true,
      events: events,
    );

    await tester.longPress(find.byKey(const ValueKey('album_tile_2')));
    await tester.pump();

    expect(events, ['menu:2']);
  });

  testBothViewports('opens the menu from its button, without selecting', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpTile(
      tester,
      size: size,
      expandedIds: const {1},
      withMenu: true,
      events: events,
    );

    await tester.tap(find.byKey(const ValueKey('album_menu_3')));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(events, ['menu:3']);
  });

  testBothViewports('opens the menu on a right-click', (tester, size) async {
    final events = <String>[];
    await pumpTile(tester, size: size, withMenu: true, events: events);

    await tester.tap(
      find.byKey(const ValueKey('album_tile_1')),
      buttons: kSecondaryButton,
    );
    await tester.pump();

    expect(events, ['menu:1']);
  });

  testWidgets('offers no menu button without a menu', (tester) async {
    await pumpTile(tester, size: narrowViewport, expandedIds: const {1});

    expect(find.byIcon(QuarkIcons.more_vert), findsNothing);
  });

  testWidgets('replaces the glyph for a system album', (tester) async {
    await pumpTile(
      tester,
      size: wideViewport,
      album: const AlbumItem(
        id: 5,
        name: 'Favorites',
        isSystem: true,
        isFavorites: true,
      ),
      systemIcon: QuarkIcons.star_rounded,
    );

    expect(find.byIcon(QuarkIcons.star_rounded), findsOneWidget);
    expect(find.byIcon(QuarkIcons.photo_album_outlined), findsNothing);
  });
}
