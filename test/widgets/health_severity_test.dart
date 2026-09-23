import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/health_service.dart';
import 'package:quark/widgets/health/health_severity.dart';
import 'package:quark/widgets/health/status_banner.dart';

/// #2095: the summary is the worst meter, core chip, or backend alert.
void main() {
  group('overallHealthSeverity', () {
    test('all calm readings are healthy', () {
      expect(overallHealthSeverity(_status()), HealthSeverity.healthy);
    });

    test('memory at 92.6 is a warning, under the 95 alert', () {
      expect(
        overallHealthSeverity(_status(memPercent: 92.6)),
        HealthSeverity.warning,
      );
    });

    test('memory at 96 is critical', () {
      expect(
        overallHealthSeverity(_status(memPercent: 96)),
        HealthSeverity.critical,
      );
    });

    test('one core at 100 is critical when everything else is calm', () {
      expect(
        overallHealthSeverity(_status(cpuCorePercents: const [4, 100])),
        HealthSeverity.critical,
      );
    });

    test('one core at 70 is a warning', () {
      expect(
        overallHealthSeverity(_status(cpuCorePercents: const [10, 70])),
        HealthSeverity.warning,
      );
    });

    test('healthy false is critical even when every percent is low', () {
      expect(
        overallHealthSeverity(
          _status(
            healthy: false,
            cpuPercent: 1,
            cpuCorePercents: const [1, 2],
            memPercent: 1,
            diskPercent: 1,
            temperatureCelsius: 1,
          ),
        ),
        HealthSeverity.critical,
      );
    });

    test('a backend alert is critical even when every percent is low', () {
      expect(
        overallHealthSeverity(_status(alerts: const ['disk usage high'])),
        HealthSeverity.critical,
      );
    });

    test('an orange memory meter plus a red core is critical', () {
      // The #2095 report: memory around 92.6 and one core at 100.
      expect(
        overallHealthSeverity(
          _status(memPercent: 92.6, cpuCorePercents: const [100]),
        ),
        HealthSeverity.critical,
      );
    });

    test('meter and core cutoffs match the colors the cards paint', () {
      // Memory warns at 71.25 (three quarters of 95) and is critical at 95.
      expect(
        overallHealthSeverity(_status(memPercent: 71.24)),
        HealthSeverity.healthy,
      );
      expect(
        overallHealthSeverity(_status(memPercent: 71.25)),
        HealthSeverity.warning,
      );
      expect(
        overallHealthSeverity(_status(memPercent: 95)),
        HealthSeverity.critical,
      );

      // CPU aggregate warns at 67.5, not at the core chip's 67.
      expect(
        overallHealthSeverity(_status(cpuPercent: 67.4)),
        HealthSeverity.healthy,
      );
      expect(
        overallHealthSeverity(_status(cpuPercent: 67.5)),
        HealthSeverity.warning,
      );
      expect(
        overallHealthSeverity(_status(cpuPercent: 90)),
        HealthSeverity.critical,
      );

      expect(
        overallHealthSeverity(_status(diskPercent: 67.4)),
        HealthSeverity.healthy,
      );
      expect(
        overallHealthSeverity(_status(diskPercent: 67.5)),
        HealthSeverity.warning,
      );
      expect(
        overallHealthSeverity(_status(diskPercent: 90)),
        HealthSeverity.critical,
      );

      // No sensor (0) is not a reading. A present sensor warns at 60.
      expect(
        overallHealthSeverity(_status(temperatureCelsius: 0)),
        HealthSeverity.healthy,
      );
      expect(
        overallHealthSeverity(_status(temperatureCelsius: 59.9)),
        HealthSeverity.healthy,
      );
      expect(
        overallHealthSeverity(_status(temperatureCelsius: 60)),
        HealthSeverity.warning,
      );
      expect(
        overallHealthSeverity(_status(temperatureCelsius: 80)),
        HealthSeverity.critical,
      );

      // Cores go orange at 67 and red at 90, not at 67.5.
      expect(
        overallHealthSeverity(_status(cpuCorePercents: const [66.9])),
        HealthSeverity.healthy,
      );
      expect(
        overallHealthSeverity(_status(cpuCorePercents: const [67])),
        HealthSeverity.warning,
      );
      expect(
        overallHealthSeverity(_status(cpuCorePercents: const [89.9])),
        HealthSeverity.warning,
      );
      expect(
        overallHealthSeverity(_status(cpuCorePercents: const [90])),
        HealthSeverity.critical,
      );
    });
  });

  group('StatusBanner', () {
    testWidgets('labels and colors follow the three severities', (
      tester,
    ) async {
      await _pumpBanner(tester, HealthSeverity.healthy);
      expect(find.text('All systems healthy'), findsOneWidget);
      expect(
        _cardColor(tester),
        Theme.of(
          tester.element(find.byType(StatusBanner)),
        ).colorScheme.primaryContainer,
      );

      await _pumpBanner(tester, HealthSeverity.warning);
      expect(find.text('Some readings are elevated'), findsOneWidget);
      expect(find.text('All systems healthy'), findsNothing);
      expect(_cardColor(tester), Colors.orange.shade100);

      await _pumpBanner(tester, HealthSeverity.critical);
      expect(find.text('Issues detected'), findsOneWidget);
      expect(find.text('Some readings are elevated'), findsNothing);
      expect(
        _cardColor(tester),
        Theme.of(
          tester.element(find.byType(StatusBanner)),
        ).colorScheme.errorContainer,
      );
    });

    testWidgets('lists alerts when the Quark sent any', (tester) async {
      await _pumpBanner(
        tester,
        HealthSeverity.warning,
        alerts: const ['memory high'],
      );

      expect(find.text('Some readings are elevated'), findsOneWidget);
      expect(find.text('• memory high'), findsOneWidget);
    });
  });
}

HealthStatus _status({
  bool healthy = true,
  List<String> alerts = const [],
  double cpuPercent = 10,
  List<double> cpuCorePercents = const [10, 20],
  double memPercent = 20,
  double diskPercent = 30,
  double temperatureCelsius = 40,
}) {
  return HealthStatus(
    healthy: healthy,
    alerts: alerts,
    cpuPercent: cpuPercent,
    cpuCorePercents: cpuCorePercents,
    memPercent: memPercent,
    memUsedBytes: 0,
    memTotalBytes: 0,
    diskPercent: diskPercent,
    diskUsedBytes: 0,
    diskTotalBytes: 0,
    temperatureCelsius: temperatureCelsius,
  );
}

Future<void> _pumpBanner(
  WidgetTester tester,
  HealthSeverity severity, {
  List<String> alerts = const [],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatusBanner(severity: severity, alerts: alerts),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Color? _cardColor(WidgetTester tester) {
  return tester.widget<Card>(find.byType(Card)).color;
}
