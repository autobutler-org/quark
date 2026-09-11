import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testBothViewports('draws the chevron and lets taps through', (
    tester,
    size,
  ) async {
    var taps = 0;
    await pumpAt(
      tester,
      Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
            ),
          ),
          const Positioned(top: 0, left: 0, right: 0, child: ScrollUpHint()),
        ],
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.byIcon(QuarkIcons.keyboard_arrow_up_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('scroll_up_hint')));
    expect(taps, 1);
  });
}
