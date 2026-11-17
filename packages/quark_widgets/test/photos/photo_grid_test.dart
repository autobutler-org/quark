import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
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

  testWidgets('offers double tap on remote photos only', (tester) async {
    await pumpGrid(tester);

    PhotoGridTile tile(String id) => tester.widget<PhotoGridTile>(
      find.ancestor(
        of: find.byKey(ValueKey('photo_tile_$id')),
        matching: find.byType(PhotoGridTile),
      ),
    );
    expect(tile('a').onDoubleTap, isNotNull);
    expect(tile('b').onDoubleTap, isNull);
  });

  testWidgets('offers no double tap in selection mode', (tester) async {
    await pumpGrid(tester, selectionMode: true, selectedIds: {'a'});

    expect(find.byKey(const ValueKey('photo_tile_check_a')), findsOneWidget);
    final tiles = tester.widgetList<PhotoGridTile>(find.byType(PhotoGridTile));
    expect(tiles.every((t) => t.onDoubleTap == null), isTrue);
    expect(tiles.first.isSelected, isTrue);
  });

  testWidgets('gives every tile a menu outside selection mode', (tester) async {
    final events = <String>[];
    await pumpGrid(tester, events: events, withMenu: true);

    await tester.tap(find.byKey(const ValueKey('photo_tile_menu_c')));
    // c is remote, so the tile's double tap holds the tap until it times out.
    await tester.pump(kDoubleTapTimeout);
    expect(events, ['menu:2']);
  });

  testWidgets('offers no menu on a device photo (#2276)', (tester) async {
    await pumpGrid(tester, withMenu: true);

    // b is a device photo: nothing on the Quark to act on.
    expect(find.byKey(const ValueKey('photo_tile_menu_a')), findsOneWidget);
    expect(find.byKey(const ValueKey('photo_tile_menu_b')), findsNothing);
  });

  testWidgets('a long press can stay selection with a menu', (tester) async {
    final events = <String>[];
    await pumpAt(
      tester,
      CustomScrollView(
        slivers: [
          PhotoGrid(
            photos: _photos,
            crossAxisCount: 3,
            emptyState: const SizedBox(),
            thumbnailBuilder: (context, photo) =>
                const ColoredBox(color: Colors.teal),
            onTap: (_) {},
            onLongPress: (i) => events.add('long:$i'),
            onMenu: (i, _) => events.add('menu:$i'),
            longPressOpensMenu: false,
          ),
        ],
      ),
    );

    await tester.longPress(find.byKey(const ValueKey('photo_tile_a')));
    await tester.pump();

    expect(events, ['long:0']);
  });

  testWidgets('offers no menu in selection mode', (tester) async {
    await pumpGrid(tester, withMenu: true, selectionMode: true);

    expect(find.byKey(const ValueKey('photo_tile_menu_a')), findsNothing);
  });

  testWidgets('shows a spinner while the first load has no photos', (
    tester,
  ) async {
    await pumpGrid(tester, photos: const [], isLoading: true);

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.text('No photos yet'), findsNothing);
  });

  testWidgets('keeps the photos on screen while refreshing', (tester) async {
    await pumpGrid(tester, isLoading: true);

    expect(find.byKey(const ValueKey('photo_grid')), findsOneWidget);
  });

  testWidgets('shows the error', (tester) async {
    await pumpGrid(tester, error: "Couldn't load your photos.");

    expect(find.text("Couldn't load your photos."), findsOneWidget);
    expect(find.byKey(const ValueKey('photo_grid')), findsNothing);
  });

  testWidgets('shows the caller empty state', (tester) async {
    await pumpGrid(tester, photos: const []);

    expect(find.text('No photos yet'), findsOneWidget);
  });

  testWidgets('appends a spinner cell while there is another page', (
    tester,
  ) async {
    await pumpGrid(tester, hasMore: true);

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

    testWidgets('draws no header for an empty run', (tester) async {
      await pumpGrid(
        tester,
        sections: const [
          PhotoGridSection(id: 'none', label: 'January 2025', count: 0),
          PhotoGridSection(id: 'all', label: 'December 2024', count: 3),
        ],
      );

      expect(find.text('January 2025'), findsNothing);
      expect(find.text('December 2024'), findsOneWidget);
    });

    testWidgets('appends the spinner after the last run', (tester) async {
      await pumpGrid(
        tester,
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

  testBothViewports('names every tile for a screen reader', (
    tester,
    size,
  ) async {
    await pumpGrid(tester, size: size, withMenu: true);

    await expectTapTargetGuidelines(tester);
  });

  /// #3349: a tile scrolled far enough away is disposed. Coming back builds
  /// it afresh, and its thumbnail is asked for its own photo, not whichever
  /// photo last used that slot.
  testBothViewports('rebuilds each tile with its own photo after scrolling '
      'away and back', (tester, size) async {
    final photos = [
      for (var i = 0; i < 300; i++) PhotoItem(id: 'p$i', name: 'p$i.jpg'),
    ];
    final built = <String>[];
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpAt(
      tester,
      CustomScrollView(
        controller: controller,
        slivers: [
          PhotoGrid(
            photos: photos,
            crossAxisCount: 3,
            emptyState: const SizedBox(),
            thumbnailBuilder: (context, photo) {
              built.add(photo.id);
              return Text(photo.name);
            },
            onTap: (_) {},
            onLongPress: (_) {},
          ),
        ],
      ),
      size: size,
    );
    final first = [
      for (final photo in photos)
        if (find
            .byKey(ValueKey('photo_tile_${photo.id}'))
            .evaluate()
            .isNotEmpty)
          photo,
    ];
    expect(first, isNotEmpty);

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    for (final photo in first) {
      expect(find.byKey(ValueKey('photo_tile_${photo.id}')), findsNothing);
    }

    built.clear();
    controller.jumpTo(0);
    await tester.pump();
    for (final photo in first) {
      final tile = find.byKey(ValueKey('photo_tile_${photo.id}'));
      expect(tile, findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.text(photo.name)),
        findsOneWidget,
      );
      expect(built, contains(photo.id), reason: '${photo.id} was not rebuilt');
    }
  });

  group('range and drag select (#4171)', () {
    List<PhotoItem> many(int n) => [
      for (var i = 0; i < n; i++) PhotoItem(id: 'p$i', name: 'p$i.jpg'),
    ];

    Future<void> pumpSelectable(
      WidgetTester tester,
      Size size,
      List<String> events, {
      int count = 30,
      int columns = 3,
      List<PhotoGridSection>? sections,
      ScrollController? controller,
    }) => pumpAt(
      tester,
      CustomScrollView(
        controller: controller,
        slivers: [
          PhotoGrid(
            photos: many(count),
            sections: sections,
            crossAxisCount: columns,
            selectionMode: true,
            emptyState: const SizedBox(),
            thumbnailBuilder: (context, photo) =>
                ColoredBox(color: Colors.teal, child: Text(photo.name)),
            onTap: (i) => events.add('tap:$i'),
            onLongPress: (i) => events.add('long:$i'),
            onRangeSelect: (i) => events.add('range:$i'),
            onDragSelectStart: () => events.add('start'),
            onDragSelectUpdate: (indices) =>
                events.add('drag:${indices.join(',')}'),
            onDragSelectEnd: () => events.add('end'),
          ),
        ],
      ),
      size: size,
    );

    Offset at(WidgetTester tester, int i) =>
        tester.getCenter(find.byKey(ValueKey('photo_tile_p$i')));

    testBothViewports('a shift-click reports a range, a click a tap', (
      tester,
      size,
    ) async {
      final events = <String>[];
      await pumpSelectable(tester, size, events);

      await tester.tap(find.byKey(const ValueKey('photo_tile_p0')));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.byKey(const ValueKey('photo_tile_p4')));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(events, ['tap:0', 'range:4']);
    });

    testBothViewports('a mouse drag across two rows selects the tiles it '
        'crossed', (tester, size) async {
      final events = <String>[];
      await pumpSelectable(tester, size, events);

      final drag = await tester.startGesture(
        at(tester, 0),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveTo(at(tester, 1));
      await tester.pump();
      await drag.moveTo(at(tester, 4));
      await tester.pump();
      await drag.up();
      await tester.pump();

      // A rubber band from the first row's first tile to the second row's
      // second: two rows of two, not the whole run between them.
      expect(events, ['start', 'drag:0,1', 'drag:0,1,3,4', 'end']);
    });

    testBothViewports('a long press then a swipe across a row selects it, '
        'and swiping back gives it back', (tester, size) async {
      final events = <String>[];
      await pumpSelectable(tester, size, events);

      final drag = await tester.startGesture(at(tester, 0));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await drag.moveTo(at(tester, 1));
      await tester.pump();
      await drag.moveTo(at(tester, 2));
      await tester.pump();
      await drag.moveTo(at(tester, 1));
      await tester.pump();
      await drag.moveTo(at(tester, 0));
      await tester.pump();
      await drag.up();
      await tester.pump();

      expect(events, [
        'long:0',
        'start',
        'drag:0,1',
        'drag:0,1,2',
        'drag:0,1',
        'drag:0',
        'end',
      ]);
    });

    testBothViewports('a swipe down after a long press takes the run in grid '
        'order', (tester, size) async {
      final events = <String>[];
      await pumpSelectable(tester, size, events);

      final drag = await tester.startGesture(at(tester, 1));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await drag.moveTo(at(tester, 3));
      await tester.pump();
      await drag.up();

      expect(events, ['long:1', 'start', 'drag:1,2,3', 'end']);
    });

    testBothViewports('a plain swipe scrolls and selects nothing', (
      tester,
      size,
    ) async {
      final events = <String>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpSelectable(tester, size, events, controller: controller);

      await tester.dragFrom(at(tester, 3), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(controller.offset, greaterThan(0));
      expect(events, isEmpty);
    });

    testBothViewports('a drag held at the bottom edge scrolls the grid and '
        'keeps selecting', (tester, size) async {
      final events = <String>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpSelectable(
        tester,
        size,
        events,
        count: 90,
        controller: controller,
      );

      final drag = await tester.startGesture(
        at(tester, 0),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveTo(at(tester, 1));
      await tester.pump();
      await drag.moveTo(Offset(at(tester, 1).dx, size.height - 4));
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await drag.up();
      await tester.pump();

      expect(controller.offset, greaterThan(0));
      final last = events.lastWhere((e) => e.startsWith('drag:'));
      final indices = last.substring(5).split(',').map(int.parse);
      expect(indices.reduce((a, b) => a > b ? a : b), greaterThan(15));
      expect(indices.every((i) => i % 3 != 2), isTrue, reason: 'two columns');
      expect(events.last, 'end');
    });

    testBothViewports('a rubber band counts columns within each section', (
      tester,
      size,
    ) async {
      final events = <String>[];
      await pumpSelectable(
        tester,
        size,
        events,
        count: 20,
        columns: 8,
        sections: const [
          PhotoGridSection(id: 'a', label: 'March 2025', count: 4),
          PhotoGridSection(id: 'b', label: 'February 2025', count: 16),
        ],
      );

      final drag = await tester.startGesture(
        at(tester, 2),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveTo(at(tester, 1));
      await tester.pump();
      await drag.moveTo(at(tester, 13));
      await tester.pump();
      await drag.up();

      expect(events, ['start', 'drag:1,2', 'drag:1,2,5,6,13,14', 'end']);
    });

    testWidgets('without drag callbacks a mouse drag selects nothing', (
      tester,
    ) async {
      final events = <String>[];
      await pumpGrid(tester, events: events, selectionMode: true);

      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('photo_tile_a'))),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveTo(
        tester.getCenter(find.byKey(const ValueKey('photo_tile_c'))),
      );
      await drag.up();
      await tester.pump(kDoubleTapTimeout);

      expect(events, isEmpty);
    });
  });
}
