import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The protection card. Each level renders the sentence, next step, and
/// Back up now it was given, at both viewports.
void main() {
  DataProtectionStatusCard card(
    DataProtectionLevel level, {
    String? sentence,
    String? nextStepLabel,
    VoidCallback? onNextStep,
    VoidCallback? onBackUpNow,
    VoidCallback? onExplain,
    bool isLoading = false,
    String? error,
  }) {
    return DataProtectionStatusCard(
      level: level,
      sentence: sentence ?? 'Sentence for ${level.label}.',
      nextStepLabel: nextStepLabel,
      onNextStep: onNextStep,
      onBackUpNow: onBackUpNow,
      onExplain: onExplain,
      isLoading: isLoading,
      error: error,
    );
  }

  for (final level in DataProtectionLevel.values) {
    testBothViewports('shows ${level.label}', (tester, size) async {
      await pumpAt(
        tester,
        card(
          level,
          sentence: 'Your files at ${level.label}.',
          nextStepLabel: 'Do the next thing',
          onNextStep: () {},
          onExplain: () {},
        ),
        size: size,
      );
      await tester.pumpAndSettle();

      expect(find.text(level.label), findsOneWidget);
      expect(find.text('Your files at ${level.label}.'), findsOneWidget);
      expect(find.text('Do the next thing'), findsOneWidget);
      expect(find.text('Why two backup drives?'), findsOneWidget);
      expect(find.byType(QuarkLoader), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testBothViewports('fills the meter through the level it was given', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      card(
        DataProtectionLevel.unprotected,
        sentence: 'Built-in storage is only on this Quark.',
      ),
      size: size,
    );
    await tester.pumpAndSettle();

    final unprotected = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('data_protection_meter_step_unprotected')),
    );
    final protected = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('data_protection_meter_step_protected')),
    );
    expect(
      (unprotected.decoration as BoxDecoration).color,
      QuarkTokens.dark.error,
    );
    expect(
      (protected.decoration as BoxDecoration).color,
      QuarkTokens.dark.sidebar,
    );
    expect(find.text('Protected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back up now reports a tap and is hidden without a callback', (
    tester,
  ) async {
    var taps = 0;
    await pumpAt(
      tester,
      card(DataProtectionLevel.basic, onBackUpNow: () => taps++),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('data_protection_back_up_now')));
    await tester.pump();
    expect(taps, 1);
    expect(find.text('Back up now'), findsOneWidget);

    await pumpAt(tester, card(DataProtectionLevel.basic));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('data_protection_back_up_now')),
      findsNothing,
    );
  });

  testWidgets('reports the next step and the explainer once', (tester) async {
    final events = <String>[];
    await pumpAt(
      tester,
      card(
        DataProtectionLevel.basic,
        nextStepLabel: 'Assign the backup role',
        onNextStep: () => events.add('next'),
        onExplain: () => events.add('explain'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('data_protection_next_step')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('data_protection_explain')));
    await tester.pump();

    expect(events, ['next', 'explain']);
  });

  testWidgets('hides the next step when it is not offered', (tester) async {
    await pumpAt(
      tester,
      card(
        DataProtectionLevel.basic,
        nextStepLabel: 'Assign the backup role',
        onExplain: () {},
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('data_protection_next_step')),
      findsNothing,
    );
    expect(find.text('Assign the backup role'), findsNothing);
    expect(find.text('Why two backup drives?'), findsOneWidget);
  });

  testBothViewports('shows a loader until a level arrives', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const DataProtectionStatusCard(isLoading: true),
      size: size,
    );

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.byType(DataProtectionMeter), findsNothing);
    expect(find.text('Why two backup drives?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the error it was given', (tester) async {
    await pumpAt(
      tester,
      const DataProtectionStatusCard(error: "Couldn't check the backup."),
    );

    expect(find.text("Couldn't check the backup."), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
    expect(find.byType(DataProtectionMeter), findsNothing);
  });

  testWidgets('keeps the level visible beside a refresh error', (tester) async {
    await pumpAt(
      tester,
      card(
        DataProtectionLevel.basic,
        error: "Couldn't check the backup.",
        onExplain: () {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Basic'), findsOneWidget);
    expect(find.text("Couldn't check the backup."), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
  });

  testBothViewports('survives a long sentence', (tester, size) async {
    await pumpAt(
      tester,
      SingleChildScrollView(
        child: card(
          DataProtectionLevel.protected,
          sentence: 'Your files are on 3 drives. ' * 40,
          nextStepLabel: 'Keep one backup drive somewhere else',
          onNextStep: () {},
          onBackUpNow: () {},
          onExplain: () {},
        ),
      ),
      size: size,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: the sentence uses the card foreground', (
      tester,
    ) async {
      await pumpAt(
        tester,
        card(DataProtectionLevel.basic, sentence: 'Hello'),
        brightness: brightness,
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.text('Hello')).style?.color,
        tokens.cardForeground,
      );
    });
  }
}
