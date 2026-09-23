import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/health/metric_card.dart';
import 'package:quark_icons/quark_icons.dart';

/// #2095: the banner now follows the meter, and the note names the alert
/// limit without saying nothing is wrong.
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

  testWidgets('the orange band counts as a warning and names the limit', (
    tester,
  ) async {
    await pumpCard(tester, value: 82.5);

    expect(note, findsOneWidget);
    expect(find.textContaining('Nothing is wrong'), findsNothing);
    expect(
      find.text(
        'Elevated. The summary counts this as a warning. '
        'An alert is raised at 95%.',
      ),
      findsOneWidget,
    );
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
    expect(find.textContaining('Nothing is wrong'), findsNothing);
    expect(
      find.text(
        'Elevated. The summary counts this as a warning. '
        'An alert is raised at 90%.',
      ),
      findsOneWidget,
    );
  });
}
