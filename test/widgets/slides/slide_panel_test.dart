import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/slide_panel.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart' as tap;

/// The slide panel reports every action by slide id and holds no state
/// (#1161).
void main() {
  final slides = [
    for (var i = 1; i <= 3; i++)
      Slide(
        id: 's$i',
        elements: [
          ImageElement(
            id: 'i$i',
            source: 'pics/$i.png',
            frame: ElementFrame(x: 0, y: 0, width: 960, height: 540),
          ),
        ],
      ),
  ];
  late List<String> events;

  setUp(() => events = []);

  Future<void> pumpPanel(
    WidgetTester tester, {
    required Axis axis,
    bool canDelete = true,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
      home: Scaffold(
        body: Padding(
          // Inset from the screen edge, so the tap target check measures.
          padding: const EdgeInsets.all(8),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: axis == Axis.vertical ? SlidePanel.sideWidth : 340,
              height: axis == Axis.vertical ? 600 : SlidePanel.stripHeight,
              child: SlidePanel(
                slides: slides,
                size: SlideSize.widescreen,
                selectedSlideId: 's1',
                axis: axis,
                canDelete: canDelete,
                onSelect: (id) => events.add('select $id'),
                onAdd: () => events.add('add'),
                onDuplicate: (id) => events.add('duplicate $id'),
                onDelete: (id) => events.add('delete $id'),
                onMove: (id, to) => events.add('move $id $to'),
                onSelectPrevious: () => events.add('previous'),
                onSelectNext: () => events.add('next'),
                onPresent: (id) => events.add('present $id'),
                imageBuilder: (context, image) =>
                    Text(image.source, key: ValueKey('img_${image.source}')),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  for (final (name, size, axis) in [
    ('narrow', tap.narrowViewport, Axis.horizontal),
    ('wide', tap.wideViewport, Axis.vertical),
  ]) {
    testWidgets('selects, adds and runs the menu ($name)', (tester) async {
      tap.setViewport(tester, size);
      await pumpPanel(tester, axis: axis);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('slide_thumb_s1')));
      await tester.tap(find.byKey(const ValueKey('slide_panel_add')));
      await tester.tap(find.byKey(const ValueKey('slide_menu_s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slide_duplicate_s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slide_menu_s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slide_move_later_s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slide_menu_s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slide_present_s1')));
      await tester.pumpAndSettle();

      expect(events, [
        'select s1',
        'add',
        'duplicate s1',
        'move s1 1',
        'present s1',
      ]);
    });
  }

  testWidgets('the first slide cannot move earlier, nor the last one go', (
    tester,
  ) async {
    tap.setViewport(tester, tap.wideViewport);
    await pumpPanel(tester, axis: Axis.vertical, canDelete: false);
    await tester.tap(find.byKey(const ValueKey('slide_menu_s1')));
    await tester.pumpAndSettle();
    // Disabled rows leave the menu open.
    await tester.tap(find.byKey(const ValueKey('slide_move_earlier_s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slide_delete_s1')));
    await tester.pumpAndSettle();
    expect(events, isEmpty);
  });

  testWidgets('every thumbnail is labeled and big enough to tap', (
    tester,
  ) async {
    tap.setViewport(tester, tap.wideViewport);
    await pumpPanel(tester, axis: Axis.vertical);
    expect(find.bySemanticsLabel('Slide 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Slide 3'), findsOneWidget);
    await tap.expectTapTargetGuidelines(tester);
  });

  for (final (name, size, axis) in [
    ('narrow', tap.narrowViewport, Axis.horizontal),
    ('wide', tap.wideViewport, Axis.vertical),
  ]) {
    testWidgets('the arrow keys step once the panel has focus ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      await pumpPanel(tester, axis: axis);
      await tester.pumpAndSettle();
      // No focus yet: the keys go elsewhere.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(events, isEmpty);

      await tester.tap(find.byKey(const ValueKey('slide_thumb_s2')));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(events, ['select s2', 'next', 'next', 'previous', 'previous']);
    });

    testWidgets('thumbnails draw read-only, pictures and all ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      await pumpPanel(tester, axis: axis);
      await tester.pumpAndSettle();
      final canvas = find.descendant(
        of: find.byKey(const ValueKey('slide_thumb_s1')),
        matching: find.byType(SlideCanvas),
      );
      expect(tester.widget<SlideCanvas>(canvas).readOnly, isTrue);
      expect(
        find.ancestor(of: canvas, matching: find.byType(RepaintBoundary)),
        findsWidgets,
      );
      expect(find.byKey(const ValueKey('img_pics/1.png')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the selected thumbnail is marked selected', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    await pumpPanel(tester, axis: Axis.vertical);
    await tester.pumpAndSettle();
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byKey(const ValueKey('slide_thumb_s1'))),
      matchesSemantics(
        label: 'Slide 1',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('draws thumbnails in the theme and splits the add button '
      '(#1163)', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: Scaffold(
          body: SizedBox(
            width: SlidePanel.sideWidth,
            height: 600,
            child: SlidePanel(
              slides: slides,
              size: SlideSize.widescreen,
              selectedSlideId: 's1',
              axis: Axis.vertical,
              canDelete: true,
              theme: SlideThemes.warm,
              layouts: SlideMaster.standard.layouts,
              onAddWithLayout: (id) => events.add('add $id'),
              onSelect: (_) {},
              onAdd: () => events.add('add'),
              onDuplicate: (_) {},
              onDelete: (_) {},
              onMove: (_, _) {},
              onSelectPrevious: () {},
              onSelectNext: () {},
            ),
          ),
        ),
      ),
    );
    final canvas = tester.widget<SlideCanvas>(
      find.descendant(
        of: find.byKey(const ValueKey('slide_thumb_s1')),
        matching: find.byType(SlideCanvas),
      ),
    );
    expect(canvas.theme, SlideThemes.warm);

    await tester.tap(find.byKey(const ValueKey('slide_panel_add_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slide_panel_add_blank')));
    await tester.pumpAndSettle();
    expect(events, ['add blank']);
  });

  testWidgets('a slide that plays a transition wears a labeled marker', (
    tester,
  ) async {
    tap.setViewport(tester, tap.wideViewport);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: Scaffold(
          body: SizedBox(
            width: SlidePanel.sideWidth,
            height: 600,
            child: SlidePanel(
              slides: [
                Slide(id: 'a'),
                Slide(
                  id: 'b',
                  transition: const SlideTransitionSpec(
                    kind: SlideTransitionKind.push,
                    direction: SlideTransitionDirection.up,
                  ),
                ),
                Slide(id: 'c', transition: SlideTransitionSpec.none),
              ],
              size: SlideSize.widescreen,
              selectedSlideId: 'a',
              axis: Axis.vertical,
              canDelete: true,
              defaultTransition: const SlideTransitionSpec.fade(),
              onSelect: (_) {},
              onAdd: () {},
              onDuplicate: (_) {},
              onDelete: (_) {},
              onMove: (_, _) {},
              onSelectPrevious: () {},
              onSelectNext: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // a follows the deck's fade, b has its own push, c opts out.
    expect(
      find.byKey(const ValueKey('slide_transition_marker')),
      findsNWidgets(2),
    );
    expect(find.bySemanticsLabel('Slide 1, Fade transition'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Slide 2, Push transition, up'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Slide 3'), findsOneWidget);
    handle.dispose();
  });
}
