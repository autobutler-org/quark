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

    for (final id in const ['list', 'grid']) {
      final segment = find.ancestor(
        of: find.byKey(ValueKey('bar_segment_$id')),
        matching: find.byType(TextButton),
      );
      expect(
        tester
            .getSize(
              find.descendant(of: segment, matching: find.byType(Material)),
            )
            .height,
        QuarkBarIconButton.size,
      );
      expect(tester.getSize(segment).height, QuarkBarIconButton.tapTargetSize);
    }
    expect(find.byTooltip('Grid'), findsOneWidget);
  });

  testBothViewports('meets the tap target guidelines', (tester, size) async {
    await pumpAt(tester, toggle('list', (_) {}), size: size);

    await expectTapTargetGuidelines(tester);
  });

  testWidgets('announces which segment is on', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpAt(tester, toggle('grid', (_) {}));

    expect(
      tester.getSemantics(find.byKey(const ValueKey('bar_segment_grid'))),
      isSemantics(
        label: 'Grid',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        tooltip: 'Grid',
      ),
    );
    handle.dispose();
  });

  // #2606: the labels grow past the 36 pixel bar height instead of being cut.
  testLargeText('fits its labels', (tester, size) async {
    await pumpAt(tester, toggle('list', (_) {}), size: size);

    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
    await expectTapTargetGuidelines(tester);
  });
}
