import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The running-jobs badge: hidden at zero, a count otherwise, a tap out.
void main() {
  testBothViewports('renders nothing while no job runs', (tester, size) async {
    await pumpAt(tester, JobsBadge(runningCount: 0, onTap: () {}), size: size);
    expect(find.byKey(const ValueKey('jobs_badge')), findsNothing);
    expect(find.byType(Badge), findsNothing);
  });

  testBothViewports('counts the running jobs and names itself', (
    tester,
    size,
  ) async {
    await pumpAt(tester, JobsBadge(runningCount: 3, onTap: () {}), size: size);
    expect(tester.takeException(), isNull);
    expect(find.text('3'), findsOneWidget);
    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('jobs_badge')),
    );
    expect(button.tooltip, '3 jobs running');
  });

  testBothViewports('calls back once when tapped', (tester, size) async {
    final taps = <String>[];
    await pumpAt(
      tester,
      JobsBadge(runningCount: 1, onTap: () => taps.add('tap')),
      size: size,
    );
    await tester.tap(find.byKey(const ValueKey('jobs_badge')));
    await tester.pump();
    expect(taps, ['tap']);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: the count wears the primary token', (tester) async {
      await pumpAt(
        tester,
        JobsBadge(runningCount: 2, onTap: () {}),
        brightness: brightness,
      );
      final badge = tester.widget<Badge>(find.byType(Badge));
      expect(badge.backgroundColor, tokens.primary);
      expect(badge.textColor, tokens.primaryForeground);
    });
  }
}
