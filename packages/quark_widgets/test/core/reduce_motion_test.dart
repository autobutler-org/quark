import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Pumps a widget that records [reduceMotionOf] for its context, under a
/// MediaQuery with [disableAnimations] when that is given.
Future<bool> _read(WidgetTester tester, {bool? disableAnimations}) async {
  late bool reduce;
  final probe = Builder(
    builder: (context) {
      reduce = reduceMotionOf(context);
      return const SizedBox();
    },
  );
  await tester.pumpWidget(
    disableAnimations == null
        ? probe
        : MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: probe,
          ),
  );
  return reduce;
}

void main() {
  testWidgets('is false when neither flag is set', (tester) async {
    expect(await _read(tester, disableAnimations: false), isFalse);
  });

  testWidgets('is true under MediaQuery disableAnimations', (tester) async {
    expect(await _read(tester, disableAnimations: true), isTrue);
  });

  testWidgets('is true under the platform reduceMotion flag', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    expect(await _read(tester, disableAnimations: false), isTrue);
  });

  testWidgets('reads false without a MediaQuery above it', (tester) async {
    expect(await _read(tester), isFalse);
  });
}
