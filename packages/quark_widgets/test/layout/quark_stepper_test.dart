import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The one stepper behind the slide font size and table size steppers
/// (#4103): a button down, a 36px value, a button up, and an optional label.
void main() {
  const stepperKey = ValueKey('stepper');
  const valueKey = ValueKey('stepper_value');
  const lessKey = ValueKey('stepper_less');
  const moreKey = ValueKey('stepper_more');

  QuarkStepper stepper({
    String? label,
    String value = '3',
    VoidCallback? onLess,
    VoidCallback? onMore,
  }) => QuarkStepper(
    key: stepperKey,
    label: label,
    value: value,
    semanticsLabel: 'Rows ${value.isEmpty ? 'mixed' : value}',
    valueKey: valueKey,
    decrease: QuarkBarIconButton(
      key: lessKey,
      icon: QuarkIcons.remove,
      tooltip: 'Fewer rows',
      onPressed: onLess,
    ),
    increase: QuarkBarIconButton(
      key: moreKey,
      icon: QuarkIcons.add,
      tooltip: 'More rows',
      onPressed: onMore,
    ),
  );

  testBothViewports('with a label, fills its row in order', (
    tester,
    size,
  ) async {
    await pumpAt(tester, stepper(label: 'Rows'), size: size);

    expect(tester.takeException(), isNull);
    expect(find.text('Rows'), findsOneWidget);
    expect(tester.getSize(find.byKey(stepperKey)).width, size.width);
    final label = tester.getCenter(find.text('Rows')).dx;
    final less = tester.getCenter(find.byKey(lessKey)).dx;
    final value = tester.getCenter(find.byKey(valueKey)).dx;
    final more = tester.getCenter(find.byKey(moreKey)).dx;
    expect(label < less && less < value && value < more, isTrue);
  });

  testBothViewports('without a label, is as wide as its parts', (
    tester,
    size,
  ) async {
    await pumpAt(tester, Center(child: stepper()), size: size);

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(stepperKey)).width, lessThan(size.width));
  });

  testBothViewports('keeps the value at least 36px wide, even empty', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      Center(child: stepper(value: '')),
      size: size,
    );

    final gap =
        tester.getTopLeft(find.byKey(moreKey)).dx -
        tester.getTopRight(find.byKey(lessKey)).dx;
    expect(gap, greaterThanOrEqualTo(QuarkStepper.valueMinWidth));
  });

  testWidgets('reads the value as its semantics label', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpAt(tester, Center(child: stepper(value: '')));

    expect(find.bySemanticsLabel('Rows mixed'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('calls the caller back from each button', (tester) async {
    final calls = <String>[];
    await pumpAt(
      tester,
      Center(
        child: stepper(
          onLess: () => calls.add('less'),
          onMore: () => calls.add('more'),
        ),
      ),
    );

    await tester.tap(find.byKey(lessKey));
    await tester.tap(find.byKey(moreKey));
    expect(calls, ['less', 'more']);
  });

  testWidgets('a button at its limit does nothing', (tester) async {
    final calls = <String>[];
    await pumpAt(
      tester,
      Center(child: stepper(onMore: () => calls.add('more'))),
    );

    await tester.tap(find.byKey(lessKey), warnIfMissed: false);
    expect(calls, isEmpty);
  });
}
