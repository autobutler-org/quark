import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The protection card. Each level renders the sentence and next step it was
/// given, at both viewports, without counting the drives itself.
void main() {
  const drives = [
    DataProtectionDrive(id: 'usb-1', name: 'Backup', lastBackedUp: null),
  ];

  DataProtectionStatusCard card(
    DataProtectionLevel level, {
    String? sentence,
    List<DataProtectionDrive> driveRows = const [],
    String? nextStepLabel,
    VoidCallback? onNextStep,
    VoidCallback? onExplain,
    bool isLoading = false,
    String? error,
  }) {
    return DataProtectionStatusCard(
      level: level,
      sentence: sentence ?? 'Sentence for ${level.label}.',
      drives: driveRows,
      nextStepLabel: nextStepLabel,
      onNextStep: onNextStep,
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

  testBothViewports('keeps an unprotected level when two drives are listed', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      card(
        DataProtectionLevel.unprotected,
        sentence: 'Your files are only on this Quark.',
        driveRows: const [
          DataProtectionDrive(
            id: 'a',
            name: 'First',
            lastBackedUp: null,
            reason: 'No completed backup yet.',
          ),
          DataProtectionDrive(
            id: 'b',
            name: 'Second',
            lastBackedUp: null,
            reason: 'No completed backup yet.',
          ),
        ],
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

  testWidgets('shows when each drive was last backed up', (tester) async {
    await pumpAt(
      tester,
      card(
        DataProtectionLevel.protected,
        driveRows: [
          DataProtectionDrive(
            id: 'usb-1',
            name: 'Backup',
            lastBackedUp: DateTime(2026, 10, 1),
          ),
          const DataProtectionDrive(
            id: 'usb-2',
            name: 'Office',
            reason: 'The last backup is more than 30 days old.',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('data_protection_drive_usb-1')),
      findsOneWidget,
    );
    expect(find.text('Last backed up October 1, 2026'), findsOneWidget);
    expect(
      find.text('The last backup is more than 30 days old.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('data_protection_drive_usb-2_backed_up')),
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

  testBothViewports('survives a long sentence and a long drive name', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      SingleChildScrollView(
        child: card(
          DataProtectionLevel.protected,
          sentence: 'Your files are on 3 drives. ' * 40,
          driveRows: [
            DataProtectionDrive(
              id: 'long',
              name: 'Vacation drive ' * 30,
              lastBackedUp: DateTime(2026, 10, 1),
              reason: 'Kept somewhere else. ' * 20,
            ),
          ],
          nextStepLabel: 'Keep one backup drive somewhere else',
          onNextStep: () {},
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

  testWidgets('lays out the sample drives without an exception', (
    tester,
  ) async {
    await pumpAt(tester, card(DataProtectionLevel.basic, driveRows: drives));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
