import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/health_service.dart';
import 'package:quark/widgets/file_browser/file_storage_footer.dart';
import 'package:quark_widgets/quark_widgets.dart';

// The footer is the last child of the file browser's Column, so it sits flush
// against the physical bottom edge — the band where iOS draws the home
// indicator and Android its gesture bar. It drew the storage readout and
// progress bar straight into that band (#1598).
//
// These pump the footer under a MediaQuery carrying real device insets, with
// no health reading so it shows its placeholder; the layout is what's under
// test.
void main() {
  // iPhone 15 Pro portrait: 34pt home indicator band.
  const gestureInsets = EdgeInsets.only(top: 59, bottom: 34);
  // Same device rotated: shorter bottom band, insets on the sides.
  const landscapeInsets = EdgeInsets.only(left: 59, right: 59, bottom: 21);

  Future<double> pumpFooter(
    WidgetTester tester, {
    EdgeInsets insets = EdgeInsets.zero,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(padding: insets, viewPadding: insets),
          child: Scaffold(
            body: Column(children: [const Spacer(), const FileStorageFooter()]),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.view.physicalSize.height / tester.view.devicePixelRatio;
  }

  testWidgets('keeps its contents above the bottom inset', (
    WidgetTester tester,
  ) async {
    final screenHeight = await pumpFooter(tester, insets: gestureInsets);
    final safeBottom = screenHeight - gestureInsets.bottom;

    final controls = <String, Finder>{
      'the storage readout': find.text('Storage'),
      'the progress bar': find.byType(QuarkStorageBar),
    };
    for (final entry in controls.entries) {
      expect(
        tester.getRect(entry.value).bottom,
        lessThanOrEqualTo(safeBottom),
        reason: '${entry.key} must clear the home indicator',
      );
    }
  });

  testWidgets('paints the bar through the inset region', (
    WidgetTester tester,
  ) async {
    final screenHeight = await pumpFooter(tester, insets: gestureInsets);

    // The footer itself still reaches the physical bottom edge — only its
    // contents are lifted — so the home indicator sits on the footer's own
    // background instead of on bare page.
    final footer = tester.getRect(find.byType(FileStorageFooter));
    expect(footer.bottom, screenHeight);

    final content = tester.getRect(
      find
          .descendant(
            of: find.byType(FileStorageFooter),
            matching: find.byType(Row),
          )
          .first,
    );
    expect(
      footer.bottom - content.bottom,
      greaterThanOrEqualTo(gestureInsets.bottom),
      reason: 'the painted band below the content has to cover the inset',
    );
  });

  testWidgets('honors the side insets in landscape', (
    WidgetTester tester,
  ) async {
    final screenHeight = await pumpFooter(tester, insets: landscapeInsets);

    expect(
      tester.getRect(find.byType(Icon)).left,
      greaterThanOrEqualTo(landscapeInsets.left),
    );
    expect(
      tester.getRect(find.text('Storage')).bottom,
      lessThanOrEqualTo(screenHeight - landscapeInsets.bottom),
    );
  });

  testWidgets('adds no padding on a device without insets', (
    WidgetTester tester,
  ) async {
    final withoutInsets = await pumpFooter(tester);
    final bare = tester.getRect(find.byType(FileStorageFooter)).height;
    expect(
      tester.getRect(find.byType(FileStorageFooter)).bottom,
      withoutInsets,
    );

    final screenHeight = await pumpFooter(tester, insets: gestureInsets);
    expect(screenHeight, withoutInsets);
    expect(
      tester.getRect(find.byType(FileStorageFooter)).height,
      bare + gestureInsets.bottom,
      reason: 'the inset is the only thing that grows the footer',
    );
  });

  // The page owns the reading and refreshes it; the footer has to show
  // whatever it is handed on each rebuild rather than a value it cached once
  // (#2151).
  testWidgets('shows the reading it is rebuilt with', (
    WidgetTester tester,
  ) async {
    HealthStatus reading(int usedGiB) => HealthStatus(
      healthy: true,
      alerts: const [],
      cpuPercent: 0,
      cpuCorePercents: const [],
      memPercent: 0,
      memUsedBytes: 0,
      memTotalBytes: 0,
      diskPercent: usedGiB.toDouble(),
      diskUsedBytes: usedGiB << 30,
      diskTotalBytes: 100 << 30,
      temperatureCelsius: 0,
    );
    Future<void> pumpWith(HealthStatus? status) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Spacer(),
              FileStorageFooter(status: status),
            ],
          ),
        ),
      ),
    );

    await pumpWith(null);
    expect(find.text('Storage'), findsOneWidget);

    await pumpWith(reading(10));
    expect(find.text('10.0 GB / 100.0 GB'), findsOneWidget);
    expect(find.text('10%'), findsOneWidget);

    await pumpWith(reading(25));
    expect(find.text('25.0 GB / 100.0 GB'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
  });
}
