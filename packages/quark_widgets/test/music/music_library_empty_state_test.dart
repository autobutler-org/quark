import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The library's scanning and settled-empty states, including the scan action.
void main() {
  testBothViewports('shows scanning state without the empty action', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      MusicLibraryEmptyState(isScanning: true, onScan: () {}),
      size: size,
    );

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.text('Scanning your music'), findsOneWidget);
    expect(find.text('No music yet'), findsNothing);
    expect(find.byKey(const ValueKey('music_scan')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('shows the settled empty state and reports scan', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      MusicLibraryEmptyState(onScan: () => events.add('scan')),
      size: size,
    );

    expect(find.byType(QuarkLoader), findsNothing);
    expect(find.text('No music yet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('music_scan')));
    await tester.pump();

    expect(events, ['scan']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('omits the scan button when the callback is absent', (
    tester,
  ) async {
    await pumpAt(tester, const MusicLibraryEmptyState());

    expect(find.byKey(const ValueKey('music_scan')), findsNothing);
  });

  for (final (brightness, tokens) in [
    (Brightness.dark, QuarkTokens.dark),
    (Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$brightness: scanning copy uses tokens', (tester) async {
      await pumpAt(
        tester,
        const MusicLibraryEmptyState(isScanning: true),
        brightness: brightness,
      );

      expect(
        tester
            .widget<Text>(find.text('Looking for audio files on your devices.'))
            .style
            ?.color,
        tokens.mutedForeground,
      );
    });
  }
}
