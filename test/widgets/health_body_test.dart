import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/health_service.dart';
import 'package:quark/widgets/health/health_body.dart';

/// #2011: the disk line has to say it is the whole disk, including system
/// software, the same scope the Files footer already names.
void main() {
  testWidgets('the disk card names the whole disk, not a percent change', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await AppSettings.instance.addHost(
      HostEntry(name: 'Local', hostAddress: 'http://localhost:8080'),
    );

    const used = 16 * 1024 * 1024 * 1024;
    const total = 128 * 1024 * 1024 * 1024;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HealthBody(
            status: HealthStatus(
              healthy: true,
              alerts: [],
              cpuPercent: 10,
              cpuCorePercents: [],
              memPercent: 20,
              memUsedBytes: 0,
              memTotalBytes: 0,
              diskPercent: 12.5,
              diskUsedBytes: used,
              diskTotalBytes: total,
              temperatureCelsius: 0,
            ),
            error: null,
            isInitialLoad: false,
            onRetry: _noop,
            onManageHosts: _noop,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Disk'), findsOneWidget);
    expect(find.text('12.5%'), findsOneWidget);
    expect(
      find.text(
        '16.0 GB used of 128.0 GB · whole disk, including system software',
      ),
      findsOneWidget,
    );
    expect(find.text('0 B used of 0 B'), findsOneWidget);
  });
}

void _noop() {}
