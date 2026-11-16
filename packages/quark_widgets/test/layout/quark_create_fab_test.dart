import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// #4150: the bottom `+` Files and Photos share.
void main() {
  Widget fab({bool visible = true, VoidCallback? onPressed}) => Align(
    alignment: Alignment.bottomRight,
    child: QuarkCreateFab(
      key: const ValueKey('fab'),
      tooltip: 'Upload',
      visible: visible,
      onPressed: onPressed ?? () {},
    ),
  );

  testBothViewports('carries its tooltip', (tester, size) async {
    await pumpAt(tester, fab(), size: size);
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Upload'), findsOneWidget);
  });

  testWidgets('runs onPressed while visible', (tester) async {
    var taps = 0;
    await pumpAt(tester, fab(onPressed: () => taps++));
    await tester.tap(find.byKey(const ValueKey('fab')));
    expect(taps, 1);
  });

  testWidgets('fades out and lets taps through when hidden', (tester) async {
    var taps = 0;
    await pumpAt(tester, fab(visible: false, onPressed: () => taps++));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fab')), warnIfMissed: false);
    expect(taps, 0);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
  });

  testWidgets('skips the fade under reduced motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpAt(tester, fab(visible: false));
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).duration,
      Duration.zero,
    );
  });

  test('hides scrolling down, shows scrolling up and at the top', () {
    bool after(double offset, double delta, bool visible) =>
        QuarkCreateFab.visibleAfterScroll(
          offset: offset,
          delta: delta,
          visible: visible,
        );
    expect(after(100, 10, true), isFalse);
    expect(after(100, -10, false), isTrue);
    expect(after(100, 2, true), isTrue, reason: 'within the slop');
    expect(after(0, 10, false), isTrue, reason: 'the top always shows it');
  });
}
