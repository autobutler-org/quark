import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _photos = [
  PhotoItem(id: 'a', name: 'a.jpg'),
  PhotoItem(id: 'b', name: 'b.jpg', isRemote: false),
  PhotoItem(id: 'c', name: 'c.jpg'),
];

void main() {
  Future<void> pumpGrid(
    WidgetTester tester, {
    Size size = wideViewport,
    List<PhotoItem> photos = _photos,
    bool isLoading = false,
    String? error,
    bool hasMore = false,
    bool isLoadingMore = false,
    bool selectionMode = false,
    Set<String> selectedIds = const {},
    List<String>? events,
  }) {
    void record(String e) => events?.add(e);
    return pumpAt(
      tester,
      CustomScrollView(
        slivers: [
          PhotoGrid(
            photos: photos,
            crossAxisCount: 3,
            isLoading: isLoading,
            error: error,
            hasMore: hasMore,
            isLoadingMore: isLoadingMore,
            selectionMode: selectionMode,
            selectedIds: selectedIds,
            emptyState: const Center(child: Text('No photos yet')),
            thumbnailBuilder: (context, photo) =>
                ColoredBox(color: Colors.teal, child: Text(photo.name)),
            onTap: (i) => record('tap:$i'),
            onLongPress: (i) => record('long:$i'),
            onDoubleTap: (i) => record('double:$i'),
          ),
        ],
      ),
      size: size,
    );
  }

  testBothViewports('lays out every photo and reports taps by index', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpGrid(tester, size: size, events: events);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('photo_grid')), findsOneWidget);
    expect(find.text('c.jpg'), findsOneWidget);

    // b is a device photo, so no double tap is waiting to swallow its tap.
    await tester.tap(find.byKey(const ValueKey('photo_tile_b')));
    await tester.longPress(find.byKey(const ValueKey('photo_tile_c')));
    await tester.pump();

    expect(events, ['tap:1', 'long:2']);
  });

  testBothViewports('offers double tap on remote photos only', (
    tester,
    size,
  ) async {
    await pumpGrid(tester, size: size);

    PhotoGridTile tile(String id) => tester.widget<PhotoGridTile>(
      find.ancestor(
        of: find.byKey(ValueKey('photo_tile_$id')),
        matching: find.byType(PhotoGridTile),
      ),
    );
    expect(tile('a').onDoubleTap, isNotNull);
    expect(tile('b').onDoubleTap, isNull);
  });

  testBothViewports('offers no double tap in selection mode', (
    tester,
    size,
  ) async {
    await pumpGrid(tester, size: size, selectionMode: true, selectedIds: {'a'});

    expect(find.byKey(const ValueKey('photo_tile_check_a')), findsOneWidget);
    final tiles = tester.widgetList<PhotoGridTile>(find.byType(PhotoGridTile));
    expect(tiles.every((t) => t.onDoubleTap == null), isTrue);
    expect(tiles.first.isSelected, isTrue);
  });

  testBothViewports('shows a spinner while the first load has no photos', (
    tester,
    size,
  ) async {
    await pumpGrid(tester, size: size, photos: const [], isLoading: true);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No photos yet'), findsNothing);
  });

  testBothViewports('keeps the photos on screen while refreshing', (
    tester,
    size,
  ) async {
    await pumpGrid(tester, size: size, isLoading: true);

    expect(find.byKey(const ValueKey('photo_grid')), findsOneWidget);
  });

  testBothViewports('shows the error', (tester, size) async {
    await pumpGrid(tester, size: size, error: "Couldn't load your photos.");

    expect(find.text("Couldn't load your photos."), findsOneWidget);
    expect(find.byKey(const ValueKey('photo_grid')), findsNothing);
  });

  testBothViewports('shows the caller empty state', (tester, size) async {
    await pumpGrid(tester, size: size, photos: const []);

    expect(find.text('No photos yet'), findsOneWidget);
  });

  testBothViewports('appends a spinner cell while there is another page', (
    tester,
    size,
  ) async {
    await pumpGrid(tester, size: size, hasMore: true);

    expect(
      find.byKey(const ValueKey('photo_grid_loading_more')),
      findsOneWidget,
    );
  });
}
