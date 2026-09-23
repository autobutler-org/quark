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

  testWidgets('stands as tall as a bar icon button', (tester) async {
    await pumpAt(tester, toggle('grid', (_) {}), size: narrowViewport);

    expect(
      tester.getSize(find.byType(SegmentedButton<String>)).height,
      QuarkBarIconButton.size,
    );
    expect(find.byTooltip('Grid'), findsOneWidget);
  });
}
