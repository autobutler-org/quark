import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/health/metric_card.dart';
import 'package:quark_icons/quark_icons.dart';

/// #2048: Health showed a green "All systems healthy" banner over a memory
/// meter painted warning-orange at 82.5%, with nothing to explain the
/// contradiction. Both were telling the truth about different rules — the
/// Quark alerts on memory at 95%, the meter turns orange at three quarters of
/// that, 71.25% — and the meter is where the explanation belongs.
void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required double value,
    double criticalThreshold = 95,
    String label = 'Memory',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MetricCard(
            label: label,
            icon: QuarkIcons.storage,
            value: value,
            unit: '%',
            criticalThreshold: criticalThreshold,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final note = find.byKey(const ValueKey('metric_note_memory'));

  testWidgets('a calm meter says nothing extra', (tester) async {
    await pumpCard(tester, value: 40);

    expect(note, findsNothing);
  });

  testWidgets('the orange band says it is normal and names the limit', (
    tester,
  ) async {
    await pumpCard(tester, value: 82.5);

    expect(note, findsOneWidget);
    expect(find.textContaining('Elevated'), findsOneWidget);
    // The number the Quark actually alerts on, not the one the color uses.
    expect(find.textContaining('95%'), findsOneWidget);
  });

  testWidgets('a value over the limit says an alert is raised', (tester) async {
    await pumpCard(tester, value: 96);

    expect(find.textContaining('raises an alert'), findsOneWidget);
  });

  testWidgets('the band follows the metric, not a fixed percentage', (
    tester,
  ) async {
    // Disk alerts at 90, so its orange band starts at 67.5.
    await pumpCard(tester, value: 70, criticalThreshold: 90, label: 'Disk');

    expect(find.byKey(const ValueKey('metric_note_disk')), findsOneWidget);
    expect(find.textContaining('90%'), findsOneWidget);
  });
}
