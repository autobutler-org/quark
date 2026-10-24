import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    bool withSort = false,
    AlbumSort sort = AlbumSort.nameAsc,
    bool isSectionExpanded = true,
    bool withSectionToggle = false,
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
      onAlbumMenu: (a, _) => record('menu:${a.id}'),
      onAllPhotosSelected: withAllPhotos ? () => record('all') : null,
      sort: sort,
      onSortChanged: withSort ? (s) => record('sort:${s.id}') : null,
      isSectionExpanded: isSectionExpanded,
      onToggleSection: withSectionToggle ? () => record('section') : null,
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

  testWidgets('gives system albums their glyph and no menu', (tester) async {
    await pumpAt(tester, bounded(sidebar()));

    expect(find.byIcon(QuarkIcons.star_rounded), findsOneWidget);
    final tiles = tester.widgetList<AlbumTreeTile>(find.byType(AlbumTreeTile));
    expect(tiles.firstWhere((t) => t.album.id == 1).onMenu, isNull);
    expect(tiles.firstWhere((t) => t.album.id == 2).onMenu, isNotNull);
    expect(find.byKey(const ValueKey('album_menu_1')), findsNothing);
    expect(find.byKey(const ValueKey('album_menu_2')), findsOneWidget);
  });

  testWidgets('opens a user album menu from its button', (tester) async {
    final events = <String>[];
    await pumpAt(tester, bounded(sidebar(events: events)));

    await tester.tap(find.byKey(const ValueKey('album_menu_2')));
    await tester.pump();

    expect(events, ['menu:2']);
  });

  testWidgets('leaves out the sort button without its callback', (
    tester,
  ) async {
    await pumpAt(tester, bounded(sidebar()));

    expect(find.byKey(const ValueKey('album_sort')), findsNothing);
  });

  testBothViewports('offers every order, checks the current one, and reports', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      bounded(sidebar(withSort: true, sort: AlbumSort.newest, events: events)),
      size: size,
    );

    await tester.tap(find.byKey(const ValueKey('album_sort')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final option in AlbumSort.values) {
      expect(
        find.byKey(ValueKey('album_sort_option_${option.id}')),
        findsOneWidget,
      );
    }
    final newest = tester.widget<MenuItemButton>(
      find.byKey(const ValueKey('album_sort_option_newest')),
    );
    final oldest = tester.widget<MenuItemButton>(
      find.byKey(const ValueKey('album_sort_option_oldest')),
    );
    expect(newest.trailingIcon, isNotNull);
    expect(oldest.trailingIcon, isNull);

    await tester.tap(find.byKey(const ValueKey('album_sort_option_name_desc')));
    await tester.pumpAndSettle();

    expect(events, ['sort:name_desc']);
  });

  testWidgets('shows a loader while loading', (tester) async {
    await pumpAt(
      tester,
      bounded(sidebar(isLoading: true, withAllPhotos: true)),
    );

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Trips'), findsNothing);
    expect(find.byKey(_allPhotos), findsOneWidget);
  });

  // A Material progress bar sweeps whatever the reduced-motion flags say
  // (#2607); the loader pulses instead.
  testBothViewports('keeps a pulsing loader under reduced motion', (
    tester,
    size,
  ) async {
    reduceMotion(tester);
    await pumpAt(tester, bounded(sidebar(isLoading: true)), size: size);

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(findProgressIndicators(), findsNothing);
  });

  testWidgets('says so when there are no albums', (tester) async {
    await pumpAt(
      tester,
      bounded(sidebar(albums: const [], withAllPhotos: true)),
    );

    expect(find.text('No albums yet'), findsOneWidget);
    expect(find.byKey(_allPhotos), findsOneWidget);
  });

  testWidgets('shows the error', (tester) async {
    await pumpAt(
      tester,
      bounded(
        sidebar(error: "Couldn't load your albums.", withAllPhotos: true),
      ),
    );

    expect(find.text("Couldn't load your albums."), findsOneWidget);
    expect(find.byKey(_allPhotos), findsOneWidget);
  });

  testWidgets('leaves out All photos without its callback', (tester) async {
    await pumpAt(tester, bounded(sidebar()));

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

  testWidgets('highlights All photos when no album is selected', (
    tester,
  ) async {
    await pumpAt(tester, bounded(sidebar(withAllPhotos: true)));

    final allPhotosTint = rowTint(tester, find.byKey(_allPhotos));
    expect(allPhotosTint, isNotNull);
    expect(labelWeight(tester, 'All photos'), FontWeight.w600);
    expect(rowTint(tester, find.byKey(const ValueKey('album_tile_2'))), isNull);

    // Same highlight as a selected album, not merely some highlight.
    await pumpAt(
      tester,
      bounded(sidebar(withAllPhotos: true, selectedAlbumId: 2)),
    );
    expect(
      rowTint(tester, find.byKey(const ValueKey('album_tile_2'))),
      allPhotosTint,
    );
  });

  testWidgets('highlights the selected album instead', (tester) async {
    await pumpAt(
      tester,
      bounded(sidebar(withAllPhotos: true, selectedAlbumId: 2)),
    );

    expect(rowTint(tester, find.byKey(_allPhotos)), isNull);
    expect(labelWeight(tester, 'All photos'), FontWeight.normal);
    expect(
      rowTint(tester, find.byKey(const ValueKey('album_tile_2'))),
      isNotNull,
    );
    expect(labelWeight(tester, 'Trips'), FontWeight.w600);
  });

  testBothViewports('meets the tap target guidelines', (tester, size) async {
    await pumpAt(
      tester,
      Padding(
        padding: const EdgeInsets.all(16),
        child: bounded(sidebar(withAllPhotos: true, withSort: true)),
      ),
      size: size,
    );

    expect(
      tester
          .getSize(find.byKey(const ValueKey('album_sidebar_all_photos')))
          .height,
      greaterThanOrEqualTo(48),
    );
    for (final key in const ['album_create', 'album_sort']) {
      expect(tester.getSize(find.byKey(ValueKey(key))), const Size.square(48));
    }
    await expectTapTargetGuidelines(tester);
  });

  group('whole-section collapse (#3112)', () {
    const toggle = ValueKey('album_section_toggle');

    testWidgets('leaves the label plain without its callback', (tester) async {
      await pumpAt(tester, bounded(sidebar()));

      expect(find.byKey(toggle), findsNothing);
      expect(find.text('Albums'), findsOneWidget);
    });

    testWidgets('reports a tap, and Enter from the keyboard', (tester) async {
      final events = <String>[];
      await pumpAt(
        tester,
        bounded(sidebar(withSectionToggle: true, events: events)),
      );

      expect(find.byTooltip('Collapse albums'), findsOneWidget);
      await tester.tap(find.byKey(toggle));
      Focus.of(tester.element(find.text('Albums'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(events, ['section', 'section']);
    });

    for (final shrinkWrap in [false, true]) {
      final layout = shrinkWrap ? 'shrink-wrapped' : 'bounded';

      testBothViewports('collapsed and $layout, drops every row from layout, '
          'focus and semantics, and keeps the header actions', (
        tester,
        size,
      ) async {
        final handle = tester.ensureSemantics();
        final events = <String>[];
        Widget build({required bool expanded}) {
          final child = sidebar(
            shrinkWrap: shrinkWrap,
            isSectionExpanded: expanded,
            withSectionToggle: true,
            withAllPhotos: true,
            withSort: true,
            events: events,
          );
          return shrinkWrap
              ? SingleChildScrollView(child: child)
              : bounded(child);
        }

        await pumpAt(tester, build(expanded: true), size: size);
        final expandedHeight = tester.getSize(find.byType(AlbumSidebar)).height;
        expect(
          tester.getSemantics(find.byKey(toggle)),
          isSemantics(isButton: true, hasExpandedState: true, isExpanded: true),
        );

        await pumpAt(tester, build(expanded: false), size: size);

        expect(tester.takeException(), isNull);
        expect(find.byKey(_allPhotos), findsNothing);
        expect(find.byType(AlbumTreeTile), findsNothing);
        expect(find.text('Trips', skipOffstage: false), findsNothing);
        expect(find.bySemanticsLabel('Trips'), findsNothing);
        expect(find.byTooltip('Expand albums'), findsOneWidget);
        expect(
          tester.getSemantics(find.byKey(toggle)),
          isSemantics(
            isButton: true,
            hasExpandedState: true,
            isExpanded: false,
          ),
        );
        if (shrinkWrap) {
          expect(
            tester.getSize(find.byType(AlbumSidebar)).height,
            lessThan(expandedHeight),
          );
        }

        // Tab walks the header and nothing else.
        final focused = <Key?>{};
        for (var i = 0; i < 6; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          final context = primaryFocus?.context;
          if (context == null) continue;
          focused.add(
            context.findAncestorWidgetOfExactType<AlbumTreeTile>()?.key ??
                context.findAncestorWidgetOfExactType<TextButton>()?.key ??
                context.findAncestorWidgetOfExactType<IconButton>()?.key,
          );
        }
        expect(focused, {
          toggle,
          const ValueKey('album_sort'),
          const ValueKey('album_create'),
        });

        await tester.tap(find.byKey(const ValueKey('album_create')));
        await tester.tap(find.byKey(const ValueKey('album_sort')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('album_sort_option_name_desc')),
        );
        await tester.pumpAndSettle();
        expect(events, ['create', 'sort:name_desc']);
        handle.dispose();
      });
    }

    testWidgets('collapsed, hides the loader, the error and the empty '
        'hint too', (tester) async {
      for (final collapsed in [
        sidebar(isSectionExpanded: false, isLoading: true),
        sidebar(isSectionExpanded: false, error: 'Nope'),
        sidebar(isSectionExpanded: false, albums: const []),
      ]) {
        await pumpAt(tester, bounded(collapsed));
        expect(find.byType(QuarkLoader), findsNothing);
        expect(find.text('Nope'), findsNothing);
        expect(find.text('No albums yet'), findsNothing);
      }
    });

    testBothViewports('turns the chevron, and snaps it under reduced motion', (
      tester,
      size,
    ) async {
      Duration duration() => tester
          .widget<AnimatedRotation>(find.byType(AnimatedRotation))
          .duration;

      await pumpAt(
        tester,
        bounded(sidebar(withSectionToggle: true)),
        size: size,
      );
      expect(duration(), greaterThan(Duration.zero));

      reduceMotion(tester);
      await pumpAt(
        tester,
        bounded(sidebar(withSectionToggle: true, isSectionExpanded: false)),
        size: size,
      );
      expect(duration(), Duration.zero);

      await pumpAt(
        tester,
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: bounded(sidebar(withSectionToggle: true)),
        ),
        size: size,
      );
      expect(duration(), Duration.zero);
    });

    testBothViewports(
      'keeps a 48dp, labeled header a screen reader can press',
      (tester, size) async {
        await pumpAt(
          tester,
          Center(
            child: SizedBox(
              width: 280,
              height: 300,
              child: sidebar(withSectionToggle: true, isSectionExpanded: false),
            ),
          ),
          size: size,
        );
        await expectTapTargetGuidelines(tester);
      },
    );

    testBothViewports('names only the toggle, never a page-sized ancestor '
        '(#3642)', (tester, size) async {
      final handle = tester.ensureSemantics();
      for (final expanded in [true, false]) {
        await pumpAt(
          tester,
          bounded(
            sidebar(withSectionToggle: true, isSectionExpanded: expanded),
          ),
          size: size,
        );
        final message = expanded ? 'Collapse albums' : 'Expand albums';
        final carriers = find.semantics
            .byPredicate((node) {
              final data = node.getSemanticsData();
              return data.label.contains(message) ||
                  data.tooltip.contains(message);
            })
            .evaluate()
            .toList();

        expect(carriers, hasLength(1));
        final node = carriers.single;
        expect(node, same(tester.getSemantics(find.byKey(toggle))));
        expect(
          node,
          isSemantics(
            isButton: true,
            hasExpandedState: true,
            isExpanded: expanded,
            tooltip: message,
          ),
        );
        final toggleSize = tester.getSize(find.byKey(toggle));
        expect(node.rect.width, lessThanOrEqualTo(toggleSize.width));
        expect(node.rect.height, lessThanOrEqualTo(toggleSize.height));
      }
      handle.dispose();
    });
  });
}
