import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/keyboard.dart';
import '../support/pump.dart';

void main() {
  const key = ValueKey('card');

  Widget tappable({VoidCallback? onTap}) => Center(
    child: Semantics(
      button: true,
      label: 'Card',
      child: QuarkTappable(
        key: key,
        onTap: onTap,
        child: const SizedBox.square(dimension: 64),
      ),
    ),
  );

  testBothViewports('runs on a tap', (tester, size) async {
    var taps = 0;
    await pumpAt(tester, tappable(onTap: () => taps++), size: size);

    await tester.tap(find.byKey(key));
    expect(taps, 1);
    await expectTapTargetGuidelines(tester);
  });

  testBothViewports('is reachable by Tab and runs on Enter and Space', (
    tester,
    size,
  ) async {
    var taps = 0;
    await pumpAt(tester, tappable(onTap: () => taps++), size: size);

    await tabTo(tester, find.byKey(key));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(taps, 2);
  });

  testBothViewports('draws a ring in the primary color while focused', (
    tester,
    size,
  ) async {
    await pumpAt(tester, tappable(onTap: () {}), size: size);
    expect(findFocusRing(find.byKey(key)), findsNothing);

    await tabTo(tester, find.byKey(key));

    final ring = tester.widget<DecoratedBox>(findFocusRing(find.byKey(key)));
    final border = (ring.decoration as BoxDecoration).border! as Border;
    expect(border.top.color, QuarkTokens.dark.primary);
    expect(border.top.width, 2);
  });

  testBothViewports('draws a wider ring under the high-contrast theme', (
    tester,
    size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.highContrastDark(themeColor: QuarkThemeColor.classic),
        home: Scaffold(body: tappable(onTap: () {})),
      ),
    );

    await tabTo(tester, find.byKey(key));

    final ring = tester.widget<DecoratedBox>(findFocusRing(find.byKey(key)));
    final border = (ring.decoration as BoxDecoration).border! as Border;
    expect(QuarkTokens.highContrastDark.focusRingWidth, greaterThan(2));
    expect(border.top.width, QuarkTokens.highContrastDark.focusRingWidth);
  });

  testWidgets('without a handler it takes no focus', (tester) async {
    await pumpAt(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          tappable(),
          TextButton(onPressed: () {}, child: const Text('Next')),
        ],
      ),
    );

    await tabTo(tester, find.byType(TextButton));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(findFocusRing(find.byKey(key)), findsNothing);
  });
}
