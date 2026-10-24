import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The acknowledgment names the verdict in words, shows the Quark's sentence,
/// and says what happens to files already on the drive.
void main() {
  for (final verdict in DriveHealthVerdict.values) {
    testBothViewports('shows ${verdict.label} and its sentence', (
      tester,
      size,
    ) async {
      final events = <String>[];
      await pumpAt(
        tester,
        DriveHealthAcknowledgment(
          verdict: verdict,
          reason: 'Reported as ${verdict.label}.',
          requiresAcknowledgment: verdict == DriveHealthVerdict.replaceSoon,
          onConfirm: () => events.add('confirm'),
          onCancel: () => events.add('cancel'),
        ),
        size: size,
      );

      expect(find.text(verdict.label), findsOneWidget);
      expect(find.text('Reported as ${verdict.label}.'), findsOneWidget);
      for (final other in DriveHealthVerdict.values) {
        if (other == verdict) continue;
        expect(find.text(other.label), findsNothing);
      }
      expect(find.textContaining('manufacture'), findsNothing);
      expect(find.textContaining('year'), findsNothing);
      expect(tester.takeException(), isNull);
      expectNoClippedText(tester);

      await tester.tap(find.byKey(const ValueKey('drive_health_ack_cancel')));
      await tester.pump();
      expect(events, ['cancel']);
    });
  }

  testWidgets('a replace soon backup asks, and files stay', (tester) async {
    final events = <String>[];
    await pumpAt(
      tester,
      DriveHealthAcknowledgment(
        verdict: DriveHealthVerdict.replaceSoon,
        reason: 'This spinning drive is heavily used.',
        requiresAcknowledgment: true,
        keepsExistingFiles: true,
        addsBackup: true,
        onConfirm: () => events.add('confirm'),
        onCancel: () => events.add('cancel'),
      ),
    );

    expect(find.text('Replace this drive soon?'), findsOneWidget);
    expect(find.text('This spinning drive is heavily used.'), findsOneWidget);
    expect(
      find.text(
        'Files already on this drive stay. The backup is added beside them.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Continuing acknowledges that this drive should be replaced soon.',
      ),
      findsOneWidget,
    );
    expect(find.text('Use this drive anyway'), findsOneWidget);
    expect(find.textContaining('year'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('drive_health_ack_confirm')));
    await tester.pump();
    expect(events, ['confirm']);
  });

  testBothViewports('switching to a worse drive shows the stronger warning', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      DriveHealthAcknowledgment(
        verdict: DriveHealthVerdict.watch,
        reason: 'This spinning drive is heavily used.',
        strongerWarning: true,
        keepsExistingFiles: true,
        onConfirm: () {},
        onCancel: () {},
      ),
      size: size,
    );

    expect(find.text('This drive is in worse shape'), findsOneWidget);
    expect(find.text('Watch'), findsOneWidget);
    expect(
      find.text(
        'This drive is in worse health than the current default storage.',
      ),
      findsOneWidget,
    );
    expect(find.text('Files already on this drive stay.'), findsOneWidget);
    expect(find.text('The backup is added beside them.'), findsNothing);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Use this drive anyway'), findsNothing);
    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
  });

  testWidgets('replace soon and worse stack both warnings', (tester) async {
    await pumpAt(
      tester,
      const DriveHealthAcknowledgment(
        id: 'usb1',
        verdict: DriveHealthVerdict.replaceSoon,
        reason: 'The health tool is not installed.',
        strongerWarning: true,
        requiresAcknowledgment: true,
        keepsExistingFiles: true,
        onConfirm: _ignore,
        onCancel: _ignore,
      ),
    );

    expect(find.text('This drive is in worse shape'), findsOneWidget);
    expect(find.text('Replace soon'), findsOneWidget);
    expect(find.text('Unknown'), findsNothing);
    expect(find.text('Healthy'), findsNothing);
    expect(find.text('The health tool is not installed.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('drive_health_ack_usb1_warning')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('drive_health_ack_usb1_confirm')),
      findsOneWidget,
    );
    expect(find.text('Use this drive anyway'), findsOneWidget);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: the acknowledgment button uses the error color', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const DriveHealthAcknowledgment(
          verdict: DriveHealthVerdict.replaceSoon,
          requiresAcknowledgment: true,
          onConfirm: _ignore,
          onCancel: _ignore,
        ),
        brightness: brightness,
      );

      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('drive_health_ack_confirm')),
      );
      expect(button.style?.backgroundColor?.resolve({}), tokens.error);
    });
  }
}

void _ignore() {}
