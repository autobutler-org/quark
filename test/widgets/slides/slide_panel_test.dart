import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/slide_panel.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart' as tap;

/// The slide panel reports every action by slide id and holds no state
/// (#1161).
void main() {
  final slides = [for (var i = 1; i <= 3; i++) Slide(id: 's$i')];
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

      expect(events, ['select s1', 'add', 'duplicate s1', 'move s1 1']);
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
}
