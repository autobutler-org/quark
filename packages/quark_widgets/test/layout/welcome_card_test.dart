import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// [WelcomeCard] greets whoever just arrived on a page (#2022): a headline,
/// an optional line, the caller's start-here actions, and a dismiss button
/// only when the caller can act on one.
void main() {
  const dismissKey = ValueKey('welcome_card_dismiss');
  const actionKeys = [
    ValueKey('welcome_upload'),
    ValueKey('welcome_new_folder'),
    ValueKey('welcome_vault'),
  ];

  List<Widget> chips(List<String> events) => [
    QuarkBarChip(
      key: actionKeys[0],
      icon: QuarkIcons.upload_rounded,
      label: 'Upload',
      keepLabel: true,
      onPressed: () => events.add('upload'),
    ),
    QuarkBarChip(
      key: actionKeys[1],
      icon: QuarkIcons.create_new_folder_outlined,
      label: 'New folder',
      keepLabel: true,
      onPressed: () => events.add('folder'),
    ),
    QuarkBarChip(
      key: actionKeys[2],
      icon: QuarkIcons.lock_outline,
      label: 'Open Vault',
      keepLabel: true,
      onPressed: () => events.add('vault'),
    ),
  ];

  testBothViewports('shows the headline alone as a single line', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const WelcomeCard(headline: 'Welcome back, ada'),
      size: size,
    );

    expect(find.text('Welcome back, ada'), findsOneWidget);
    expect(find.byType(QuarkToolbar), findsNothing);
    expect(find.byKey(dismissKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('shows the message and every action with its label', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      WelcomeCard(
        headline: 'Welcome, ada',
        message: 'Start by adding something.',
        actions: chips([]),
        onDismiss: () {},
      ),
      size: size,
    );

    expect(find.text('Welcome, ada'), findsOneWidget);
    expect(find.text('Start by adding something.'), findsOneWidget);
    for (final key in actionKeys) {
      expect(find.byKey(key), findsOneWidget);
    }
    expect(find.text('Upload'), findsOneWidget);
    expect(find.text('New folder'), findsOneWidget);
    expect(find.text('Open Vault'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('reports each action and the dismissal exactly once', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      WelcomeCard(
        headline: 'Welcome, ada',
        actions: chips(events),
        onDismiss: () => events.add('dismiss'),
      ),
      size: size,
    );

    for (final key in actionKeys) {
      await tester.tap(find.byKey(key));
      await tester.pump();
    }
    await tester.tap(find.byKey(dismissKey));
    await tester.pump();

    expect(events, ['upload', 'folder', 'vault', 'dismiss']);
  });

  testWidgets('the dismiss button names itself', (tester) async {
    await pumpAt(tester, WelcomeCard(headline: 'Welcome', onDismiss: () {}));

    expect(find.byTooltip('Dismiss'), findsOneWidget);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: colors come from the tokens', (tester) async {
      await pumpAt(
        tester,
        const WelcomeCard(headline: 'Welcome'),
        brightness: brightness,
      );

      expect(tester.takeException(), isNull);
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(WelcomeCard),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, tokens.card);
      expect(decoration.border, Border.all(color: tokens.border));
    });
  }

  testBothViewports('survives a long headline and a long message', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      WelcomeCard(
        headline: 'Welcome, ${'ada' * 60}',
        message: 'Start here. ' * 40,
        actions: chips([]),
        onDismiss: () {},
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
  });

  testBothViewports('meets the tap target guidelines', (tester, size) async {
    await pumpAt(
      tester,
      Padding(
        padding: const EdgeInsets.all(16),
        child: WelcomeCard(
          headline: 'Welcome back, ada',
          actions: chips([]),
          onDismiss: () {},
        ),
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    await expectTapTargetGuidelines(tester);
  });
}
