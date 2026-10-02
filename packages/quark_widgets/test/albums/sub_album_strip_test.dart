import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _albums = [
  AlbumItem(id: 2, name: 'Reunion', parentId: 1, itemCount: 1),
  AlbumItem(
    id: 3,
    name: 'A very long sub-album name that has to fit a phone',
    parentId: 1,
    itemCount: 12,
    children: [AlbumItem(id: 4, name: 'Nested', parentId: 3)],
  ),
];

/// #2591: an album's sub-albums showed only in the sidebar tree, so nothing at
/// the top of the album's own view said it held any.
void main() {
  Future<void> pumpStrip(
    WidgetTester tester, {
    required Size size,
    List<AlbumItem> albums = _albums,
    List<String>? events,
  }) => pumpAt(
    tester,
    CustomScrollView(
      slivers: [
        SubAlbumStrip(
          albums: albums,
          onSelected: (a) => events?.add('open:${a.id}'),
        ),
        const SliverToBoxAdapter(child: Text('grid')),
      ],
    ),
    size: size,
  );

  testBothViewports('lists each sub-album above the grid and opens it', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpStrip(tester, size: size, events: events);

    expect(tester.takeException(), isNull);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Reunion'), findsOneWidget);
    expect(find.text('1 photo'), findsOneWidget);
    expect(find.text('12 photos'), findsOneWidget);
    // Only the album's own children; a grandchild opens from its parent.
    expect(find.byKey(const ValueKey('sub_album_4')), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('sub_album_2'))).dy,
      lessThan(tester.getTopLeft(find.text('grid')).dy),
    );

    await tester.tap(find.byKey(const ValueKey('sub_album_2')));
    await tester.tap(find.byKey(const ValueKey('sub_album_3')));
    expect(events, ['open:2', 'open:3']);
  });

  testBothViewports('takes no space with no sub-albums', (tester, size) async {
    await pumpStrip(tester, size: size, albums: const []);

    expect(find.byKey(const ValueKey('sub_album_strip')), findsNothing);
    expect(find.text('Albums'), findsNothing);
    expect(tester.getTopLeft(find.text('grid')).dy, 0);
  });
}
