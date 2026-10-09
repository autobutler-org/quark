import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// `reduceMotionOf` (#2607) reads both reduced-motion flags, because neither
/// one alone covers every platform.
void main() {
  Future<bool> read(WidgetTester tester, {bool disable = false}) async {
    late bool reduce;
    await pumpAt(
      tester,
      MediaQuery(
        data: MediaQueryData(disableAnimations: disable),
        child: Builder(
          builder: (context) {
            reduce = reduceMotionOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    return reduce;
  }

  testWidgets('is off when neither flag is set', (tester) async {
    expect(await read(tester), isFalse);
  });

  testWidgets('is on when animations are disabled', (tester) async {
    expect(await read(tester, disable: true), isTrue);
  });

  testWidgets('is on under platform reduce motion', (tester) async {
    reduceMotion(tester);
    expect(await read(tester), isTrue);
  });
}
