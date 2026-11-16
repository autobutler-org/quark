import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  Widget slider({
    int columns = 4,
    int minColumns = 1,
    int maxColumns = 8,
    List<int>? changes,
  }) => PhotoColumnsSlider(
    columns: columns,
    minColumns: minColumns,
    maxColumns: maxColumns,
    onColumnsChanged: (c) => changes?.add(c),
  );

  testBothViewports('lays out at both widths', (tester, size) async {
    await pumpAt(tester, slider(), size: size);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('photo_columns_slider')), findsOneWidget);
  });

  testWidgets('steps the column count within its bounds', (tester) async {
    final changes = <int>[];
    await pumpAt(tester, slider(changes: changes));

    await tester.tap(find.byKey(const ValueKey('photo_columns_less')));
    await tester.tap(find.byKey(const ValueKey('photo_columns_more')));

    expect(changes, [3, 5]);
  });

  testWidgets('disables the step past either bound', (tester) async {
    await pumpAt(tester, slider(columns: 12, minColumns: 3, maxColumns: 3));

    IconButton button(String key) =>
        tester.widget<IconButton>(find.byKey(ValueKey(key)));
    expect(button('photo_columns_less').onPressed, isNull);
    expect(button('photo_columns_more').onPressed, isNull);
  });

  testBothViewports('meets the tap target guidelines', (tester, size) async {
    await pumpAt(tester, slider(), size: size);

    await expectTapTargetGuidelines(tester);
  });
}
