// cspell:words reallocated
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// Readings the Quark can attach to a drive. The panel shows a row only when
/// the field is present, and power-on hours never become a manufacture year.
const _full = DriveHealth(
  verdict: DriveHealthVerdict.replaceSoon,
  reason: 'This spinning drive is heavily used.',
  smartStatus: 'failed',
  reallocatedSectors: 12,
  pendingSectors: 3,
  powerOnHours: 60000,
  temperatureCelsius: 41,
  media: 'spinning',
  linkSpeed: 'USB 2.0',
  speedClass: 'slow',
);

void main() {
  for (final verdict in DriveHealthVerdict.values) {
    testBothViewports('shows ${verdict.label} sentence', (tester, size) async {
      await pumpAt(
        tester,
        DriveHealthDetail(
          health: DriveHealth(
            verdict: verdict,
            reason: 'Reported as ${verdict.label}.',
          ),
          expanded: false,
          onExpandedChanged: (_) {},
        ),
        size: size,
      );

      expect(find.text('Reported as ${verdict.label}.'), findsOneWidget);
      expect(find.text('Show details'), findsNothing);
      expect(tester.takeException(), isNull);
      expectNoClippedText(tester);
    });
  }

  testBothViewports('hides readings the Quark did not send', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      DriveHealthDetail(
        health: const DriveHealth(
          verdict: DriveHealthVerdict.unknown,
          reason: 'The health tool is not installed.',
        ),
        expanded: true,
        onExpandedChanged: (_) {},
      ),
      size: size,
    );

    expect(find.text('The health tool is not installed.'), findsOneWidget);
    expect(find.text('Healthy'), findsNothing);
    expect(find.text('SMART status'), findsNothing);
    expect(find.text('Reallocated sectors'), findsNothing);
    expect(find.text('Power-on hours'), findsNothing);
    expect(find.textContaining('year'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('opens only the readings that were sent', (
    tester,
    size,
  ) async {
    final opened = <bool>[];
    await pumpAt(
      tester,
      DriveHealthDetail(
        id: 'usb1',
        health: _full,
        expanded: false,
        onExpandedChanged: opened.add,
      ),
      size: size,
    );

    expect(find.text('60000 hours'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('drive_health_details_usb1')));
    await tester.pump();
    expect(opened, [true]);

    await pumpAt(
      tester,
      const DriveHealthDetail(
        id: 'usb1',
        health: _full,
        expanded: true,
        onExpandedChanged: _ignore,
      ),
      size: size,
    );

    expect(find.text('This spinning drive is heavily used.'), findsOneWidget);
    expect(find.text('failed'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('60000 hours'), findsOneWidget);
    expect(find.text('41°C'), findsOneWidget);
    expect(find.text('Spinning'), findsOneWidget);
    expect(find.text('USB 2.0'), findsOneWidget);
    expect(find.text('Slow'), findsOneWidget);
    expect(find.textContaining('manufacture'), findsNothing);
    expect(find.textContaining('year'), findsNothing);
    expect(
      find.byKey(const ValueKey('drive_health_row_usb1_hours')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
  });

  testWidgets('a healthy drive can still have an unknown speed class', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const DriveHealthDetail(
        health: DriveHealth(
          verdict: DriveHealthVerdict.healthy,
          reason: 'Nothing needs attention.',
          speedClass: 'unknown',
        ),
        expanded: true,
        onExpandedChanged: _ignore,
      ),
    );

    expect(find.text('Nothing needs attention.'), findsOneWidget);
    expect(find.text('Speed class'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('Healthy'), findsNothing);
  });

  testWidgets('a solid-state drive says solid-state', (tester) async {
    await pumpAt(
      tester,
      const DriveHealthDetail(
        health: DriveHealth(
          verdict: DriveHealthVerdict.watch,
          media: 'solid-state',
          powerOnHours: 1,
        ),
        expanded: true,
        onExpandedChanged: _ignore,
      ),
    );

    expect(find.text('Solid-state'), findsOneWidget);
    expect(find.text('1 hour'), findsOneWidget);
    expect(find.text('Spinning'), findsNothing);
  });

  testBothViewports('survives a long sentence', (tester, size) async {
    await pumpAt(
      tester,
      DriveHealthDetail(
        health: DriveHealth(
          verdict: DriveHealthVerdict.watch,
          reason: 'This spinning drive is heavily used. ' * 12,
          linkSpeed: 'USB 2.0 ' * 8,
        ),
        expanded: true,
        onExpandedChanged: (_) {},
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
  });

  testBothViewports('opens at once when animations are disabled', (
    tester,
    size,
  ) async {
    await _openUnderReducedMotion(
      tester,
      size,
      disableAnimations: true,
      platform: false,
    );
  });

  testBothViewports('opens at once when the platform asks for less motion', (
    tester,
    size,
  ) async {
    await _openUnderReducedMotion(
      tester,
      size,
      disableAnimations: false,
      platform: true,
    );
  });
}

void _ignore(bool _) {}

Future<void> _openUnderReducedMotion(
  WidgetTester tester,
  Size size, {
  required bool disableAnimations,
  required bool platform,
}) async {
  if (platform) reduceMotion(tester);
  var expanded = false;
  await pumpAt(
    tester,
    StatefulBuilder(
      builder: (context, setState) {
        final detail = DriveHealthDetail(
          health: _full,
          expanded: expanded,
          onExpandedChanged: (value) => setState(() => expanded = value),
        );
        if (!disableAnimations) return detail;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: detail,
        );
      },
    ),
    size: size,
  );

  expect(find.text('60000 hours'), findsNothing);
  await tester.tap(find.byKey(const ValueKey('drive_health_details')));
  await tester.pump();
  expect(expanded, isTrue);
  expect(find.text('60000 hours'), findsOneWidget);
  expect(tester.takeException(), isNull);
}
