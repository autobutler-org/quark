import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  Widget toggle(String selectedId, ValueChanged<String> onSelected) => Center(
    child: QuarkBarSegmentedToggle(
      segments: const [
        QuarkBarSegment(
          id: 'list',
          icon: QuarkIcons.view_list_rounded,
          label: 'List',
        ),
        QuarkBarSegment(
          id: 'grid',
          icon: QuarkIcons.grid_view_rounded,
          label: 'Grid',
        ),
      ],
      selectedId: selectedId,
      onSelected: onSelected,
    ),
  );

  testBothViewports('reports the segment the user chose', (tester, size) async {
    final chosen = <String>[];
    await pumpAt(tester, toggle('list', chosen.add), size: size);

    await tester.tap(find.byKey(const ValueKey('bar_segment_grid')));
    await tester.pump();

    expect(chosen, ['grid']);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('ignores a tap on the segment already on', (
    tester,
    size,
  ) async {
    final chosen = <String>[];
    await pumpAt(tester, toggle('list', chosen.add), size: size);

    await tester.tap(find.byKey(const ValueKey('bar_segment_list')));
    await tester.pump();

    expect(chosen, isEmpty);
  });

  testBothViewports('draws as tall as a bar icon button', (tester, size) async {
    await pumpAt(tester, toggle('grid', (_) {}), size: size);

    final toggleFinder = find.byType(QuarkBarSegmentedToggle);
    expect(drawnSize(tester, toggleFinder).height, QuarkBarIconButton.size);
    expect(tester.getSize(toggleFinder).height, QuarkBarIconButton.hitSize);
    expect(find.byTooltip('Grid'), findsOneWidget);
  });

  testBothViewports('answers taps across a 48 pixel target', (
    tester,
    size,
  ) async {
    await pumpAt(tester, toggle('grid', (_) {}), size: size);

    await expectTapTargetsMeetGuideline(tester);
  });

  testBothViewports('takes a tap just outside the frame', (tester, size) async {
    final chosen = <String>[];
    await pumpAt(tester, toggle('list', chosen.add), size: size);

    final label = tester.getRect(
      find.byKey(const ValueKey('bar_segment_grid')),
    );
    final toggleRect = tester.getRect(find.byType(QuarkBarSegmentedToggle));
    await tester.tapAt(Offset(label.center.dx, toggleRect.top + 2));
    await tester.pump();

    expect(chosen, ['grid']);
  });

  testWidgets('survives 200% text on a phone (#2606)', (tester) async {
    await expectSurvivesLargeText(tester, toggle('grid', (_) {}));

    expect(find.text('Grid'), findsOneWidget);
  });
}
