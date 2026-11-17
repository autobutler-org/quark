import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    Size size = wideViewport,
    String lead = 'My files',
    VoidCallback? onPressed,
  }) => pumpAt(
    tester,
    Column(
      children: [
        FileSortViewBar(
          lead: Text(lead, maxLines: 1, overflow: TextOverflow.ellipsis),
          sortLabel: 'Name',
          ascending: true,
          onPressed: onPressed ?? () {},
        ),
      ],
    ),
    size: size,
  );

  testBothViewports('puts the path on the left and the sort on the right', (
    tester,
    size,
  ) async {
    await pumpBar(tester, size: size);

    final chip = find.byKey(const ValueKey('file_sort_view_chip'));
    expect(chip, findsOneWidget);
    expect(
      find.descendant(of: chip, matching: find.text('Name')),
      findsOneWidget,
    );
    expect(
      tester.getCenter(find.text('My files')).dx,
      lessThan(tester.getCenter(chip).dx),
    );
    expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });

  testBothViewports('a long path gives way to the chip', (tester, size) async {
    await pumpBar(
      tester,
      size: size,
      lead: 'users / alice / ${'Documents / ' * 20}Taxes',
    );

    expect(find.byKey(const ValueKey('file_sort_view_chip')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the chip calls onPressed', (tester) async {
    var pressed = 0;
    await pumpBar(tester, onPressed: () => pressed++);

    await tester.tap(find.byKey(const ValueKey('file_sort_view_chip')));
    await tester.pump();

    expect(pressed, 1);
  });

  testWidgets('the chip says what it does', (tester) async {
    await pumpBar(tester);

    expect(find.byTooltip('Sort and view'), findsOneWidget);
  });
}
