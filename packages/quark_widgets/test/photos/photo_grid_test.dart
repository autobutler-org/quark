import 'package:flutter/gestures.dart';
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
    bool withMenu = false,
    List<PhotoGridSection>? sections,
    ScrollController? controller,
  }) {
    void record(String e) => events?.add(e);
    return pumpAt(
      tester,
      CustomScrollView(
        controller: controller,
        slivers: [
          PhotoGrid(
            photos: photos,
            sections: sections,
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
            onMenu: withMenu ? (i, _) => record('menu:$i') : null,
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

  testBothViewports('gives every tile a menu outside selection mode', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpGrid(tester, size: size, events: events, withMenu: true);

    await tester.tap(find.byKey(const ValueKey('photo_tile_menu_c')));
    // c is remote, so the tile's double tap holds the tap until it times out.
    await tester.pump(kDoubleTapTimeout);
    expect(events, ['menu:2']);
  });

  testBothViewports('offers no menu in selection mode', (tester, size) async {
    await pumpGrid(tester, size: size, withMenu: true, selectionMode: true);

    expect(find.byKey(const ValueKey('photo_tile_menu_a')), findsNothing);
  });

  testBothViewports('shows a spinner while the first load has no photos', (
    tester,
    size,
  ) async {
    await pumpGrid(tester, size: size, photos: const [], isLoading: true);

    expect(find.byType(QuarkLoader), findsOneWidget);
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

  group('sections', () {
    final many = [
      for (var i = 0; i < 60; i++) PhotoItem(id: 'p$i', name: 'p$i.jpg'),
    ];
    const split = [
      PhotoGridSection(id: '2025-03', label: 'March 2025', count: 30),
      PhotoGridSection(id: '2025-02', label: 'February 2025', count: 30),
    ];

    Rect header(WidgetTester tester, String id) =>
        tester.getRect(find.byKey(ValueKey('photo_grid_section_$id')));

    testBothViewports('heads each run and still reports whole-list indices', (
      tester,
      size,
    ) async {
      final events = <String>[];
      await pumpGrid(
        tester,
        size: size,
        events: events,
        sections: const [
          PhotoGridSection(id: 'mar', label: 'March 2025', count: 2),
          PhotoGridSection(id: 'feb', label: 'February 2025', count: 1),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('photo_grid')), findsOneWidget);
      expect(find.text('March 2025'), findsOneWidget);
      expect(find.text('February 2025'), findsOneWidget);
      expect(header(tester, 'mar').top, lessThan(header(tester, 'feb').top));

      // b is a device photo, so its tap is not held for a double tap.
      await tester.longPress(find.byKey(const ValueKey('photo_tile_c')));
      await tester.tap(find.byKey(const ValueKey('photo_tile_b')));
      await tester.pump();

      expect(events, ['long:2', 'tap:1']);
    });

    testBothViewports('pins the current header while its run scrolls past', (
      tester,
      size,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpGrid(
        tester,
        size: size,
        photos: many,
        sections: split,
        controller: controller,
      );
      final top = tester.getTopLeft(find.byType(CustomScrollView)).dy;

      controller.jumpTo(40);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(header(tester, '2025-03').top, top);

      // Deep into the second run, its header has pushed the first one out.
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();

      expect(header(tester, '2025-02').top, top);
      expect(
        find.byKey(const ValueKey('photo_grid_section_2025-03')).hitTestable(),
        findsNothing,
      );
    });

    testBothViewports('draws no header for an empty run', (tester, size) async {
      await pumpGrid(
        tester,
        size: size,
        sections: const [
          PhotoGridSection(id: 'none', label: 'January 2025', count: 0),
          PhotoGridSection(id: 'all', label: 'December 2024', count: 3),
        ],
      );

      expect(find.text('January 2025'), findsNothing);
      expect(find.text('December 2024'), findsOneWidget);
    });

    testBothViewports('appends the spinner after the last run', (
      tester,
      size,
    ) async {
      await pumpGrid(
        tester,
        size: size,
        hasMore: true,
        sections: const [
          PhotoGridSection(id: 'mar', label: 'March 2025', count: 3),
        ],
      );

      expect(
        find.byKey(const ValueKey('photo_grid_loading_more')),
        findsOneWidget,
      );
    });

    testBothViewports('survives a long label', (tester, size) async {
      await pumpGrid(
        tester,
        size: size,
        sections: [
          PhotoGridSection(id: 'long', label: 'Vacation ' * 40, count: 3),
        ],
      );

      expect(tester.takeException(), isNull);
    });

    for (final (label, brightness, tokens) in [
      ('dark', Brightness.dark, QuarkTokens.dark),
      ('light', Brightness.light, QuarkTokens.light),
    ]) {
      testWidgets('$label: the header is opaque in the background token', (
        tester,
      ) async {
        await pumpAt(
          tester,
          CustomScrollView(
            slivers: [
              PhotoGrid(
                photos: _photos,
                crossAxisCount: 3,
                sections: const [
                  PhotoGridSection(id: 'mar', label: 'March 2025', count: 3),
                ],
                emptyState: const SizedBox(),
                thumbnailBuilder: (context, photo) => const SizedBox(),
                onTap: (_) {},
                onLongPress: (_) {},
              ),
            ],
          ),
          brightness: brightness,
        );

        final box = tester.widget<ColoredBox>(
          find
              .descendant(
                of: find.byKey(const ValueKey('photo_grid_section_mar')),
                matching: find.byType(ColoredBox),
              )
              .first,
        );
        expect(box.color, tokens.background);
      });
    }
  });
}
