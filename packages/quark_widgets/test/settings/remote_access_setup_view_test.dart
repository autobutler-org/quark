import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The remote access setup sheet's content (#2857): the intro, the
/// checklist at each stage, and the done screen.
void main() {
  Semantics stepSemantics(WidgetTester tester, int n) =>
      tester.widget<Semantics>(
        find
            .descendant(
              of: find.byKey(ValueKey('remote_access_setup_step_$n')),
              matching: find.byType(Semantics),
            )
            .first,
      );

  testBothViewports('the intro turns on, or leaves', (tester, size) async {
    final taps = <String>[];
    await pumpInSheet(
      tester,
      RemoteAccessSetupView(
        stage: RemoteAccessSetupStage.intro,
        onTurnOn: () => taps.add('on'),
        onNotNow: () => taps.add('later'),
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Turn on remote access'), findsWidgets);
    expect(find.textContaining('no subscription'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('remote_access_setup_turn_on')),
    );
    await tester.tap(find.byKey(const ValueKey('remote_access_setup_turn_on')));
    await tester.ensureVisible(
      find.byKey(const ValueKey('remote_access_setup_not_now')),
    );
    await tester.tap(find.byKey(const ValueKey('remote_access_setup_not_now')));
    expect(taps, ['on', 'later']);
  });

  testBothViewports('never names the networking underneath', (
    tester,
    size,
  ) async {
    for (final stage in RemoteAccessSetupStage.values) {
      await pumpInSheet(
        tester,
        RemoteAccessSetupView(stage: stage),
        size: size,
      );
      expect(find.textContaining('Tailscale'), findsNothing);
      expect(find.textContaining('tailnet'), findsNothing);
    }
  });

  testBothViewports('preparing works on the first step', (tester, size) async {
    await pumpInSheet(
      tester,
      const RemoteAccessSetupView(stage: RemoteAccessSetupStage.preparing),
      size: size,
    );
    expect(find.text('Setting up remote access'), findsOneWidget);
    expect(
      stepSemantics(tester, 1).properties.label,
      'Preparing a private connection, in progress',
    );
    expect(
      stepSemantics(tester, 2).properties.label,
      'Connecting your Quark, waiting',
    );
    expect(
      find.byKey(const ValueKey('remote_access_setup_done')),
      findsNothing,
    );
  });

  testBothViewports('connecting has finished the first step', (
    tester,
    size,
  ) async {
    await pumpInSheet(
      tester,
      const RemoteAccessSetupView(stage: RemoteAccessSetupStage.connecting),
      size: size,
    );
    expect(
      stepSemantics(tester, 1).properties.label,
      'Preparing a private connection, done',
    );
    expect(
      stepSemantics(tester, 2).properties.label,
      'Connecting your Quark, in progress',
    );
    expect(
      stepSemantics(tester, 3).properties.label,
      'Making sure it works, waiting',
    );
  });

  testBothViewports('done ticks every step and closes', (tester, size) async {
    var closes = 0;
    await pumpInSheet(
      tester,
      RemoteAccessSetupView(
        stage: RemoteAccessSetupStage.done,
        onDone: () => closes++,
      ),
      size: size,
    );
    expect(find.text('Remote access is on'), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('remote_access_setup_done')),
    );
    await tester.tap(find.byKey(const ValueKey('remote_access_setup_done')));
    expect(closes, 1);
  });

  testLargeText('the intro survives large text', (tester, size) async {
    await pumpInSheet(
      tester,
      const RemoteAccessSetupView(stage: RemoteAccessSetupStage.intro),
      size: size,
    );
    expect(tester.takeException(), isNull);
  });
}
