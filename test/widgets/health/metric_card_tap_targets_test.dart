import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/health/metric_card.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart';

/// #2939: the per-core chips are shrink-wrapped because they are labels, not
/// controls. This pins that: nothing on the card is a target under 48dp, on a
/// phone or a desktop.
void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.linux]) {
    for (final size in [narrowViewport, wideViewport]) {
      final label = size == narrowViewport ? 'narrow' : 'wide';
      testWidgets('no target under 48dp on ${platform.name} ($label)', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        setViewport(tester, size);
        await tester.pumpWidget(
          MaterialApp(
            theme: QuarkTheme.from(QuarkTokens.light, Brightness.light),
            home: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: MetricCard(
                  label: 'CPU',
                  icon: QuarkIcons.storage,
                  value: 90,
                  unit: '%',
                  criticalThreshold: 95,
                  corePercents: [40, 95, 10, 70],
                ),
              ),
            ),
          ),
        );

        expect(find.byType(Chip), findsNWidgets(4));
        await expectTapTargetGuidelines(tester);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
