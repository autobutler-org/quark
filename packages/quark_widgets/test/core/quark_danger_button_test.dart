import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testBothViewports('spans the width it is given', (tester, size) async {
    await pumpAt(
      tester,
      QuarkDangerButton(
        key: const ValueKey('danger'),
        label: 'Empty trash',
        icon: QuarkIcons.delete_forever_outlined,
        onPressed: () {},
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    final button = tester.getSize(find.byType(OutlinedButton));
    final whole = tester.getSize(find.byKey(const ValueKey('danger')));
    expect(button.width, greaterThan(whole.width * 0.8));
    expect(find.byIcon(QuarkIcons.delete_forever_outlined), findsOneWidget);
  });

  testWidgets('reports a tap', (tester) async {
    var taps = 0;
    await pumpAt(
      tester,
      QuarkDangerButton(label: 'Empty trash', onPressed: () => taps++),
    );

    await tester.tap(find.text('Empty trash'));
    expect(taps, 1);
  });

  testWidgets('is disabled without a handler', (tester) async {
    await pumpAt(
      tester,
      const QuarkDangerButton(label: 'Empty trash', onPressed: null),
    );

    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
  });
}
