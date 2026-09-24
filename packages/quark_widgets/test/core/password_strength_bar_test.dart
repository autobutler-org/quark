import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testBothViewports('names the level for a strong password', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const PasswordStrengthBar(password: 'Tr0ub4dor&3xyz'),
      size: size,
    );
    await tester.pumpAndSettle();

    expect(find.text('Very strong'), findsOneWidget);
  });

  testBothViewports('shows no label at all for an empty password', (
    tester,
    size,
  ) async {
    await pumpAt(tester, const PasswordStrengthBar(password: ''), size: size);
    await tester.pumpAndSettle();

    expect(find.byType(Text), findsNothing);
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, 0.0);
  });

  testWidgets('animates to the fraction for the level', (tester) async {
    await pumpAt(
      tester,
      const PasswordStrengthBar(password: 'abcdefgh'),
      size: narrowViewport,
    );
    await tester.pumpAndSettle();

    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, PasswordStrength.weak.fraction);
    expect(find.text('Weak'), findsOneWidget);
  });

  testBothViewports(
    'jumps straight to the level when animations are disabled',
    (tester, size) async {
      Widget bar(String password) => MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: PasswordStrengthBar(password: password),
      );
      await pumpAt(tester, bar(''), size: size);
      await pumpAt(tester, bar('abcdefgh'), size: size);

      _expectFraction(tester, PasswordStrength.weak.fraction);
    },
  );

  testBothViewports(
    'jumps straight to the level under platform reduce motion',
    (tester, size) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await pumpAt(tester, const PasswordStrengthBar(password: ''), size: size);
      await pumpAt(
        tester,
        const PasswordStrengthBar(password: 'abcdefgh'),
        size: size,
      );

      _expectFraction(tester, PasswordStrength.weak.fraction);
    },
  );

  testWidgets('stops animating when reduce motion turns on', (tester) async {
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpAt(tester, const PasswordStrengthBar(password: ''));

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pump();
    await pumpAt(tester, const PasswordStrengthBar(password: 'abcdefgh'));

    _expectFraction(tester, PasswordStrength.weak.fraction);
  });

  group('scorePassword', () {
    test('rates an empty password as empty', () {
      expect(scorePassword(''), PasswordStrength.empty);
    });

    test('rates a short password as weak', () {
      expect(scorePassword('abc'), PasswordStrength.weak);
      expect(scorePassword('abcdefgh'), PasswordStrength.weak);
    });

    test('rates a mixed-case password of length as fair', () {
      expect(scorePassword('abcdEfgh'), PasswordStrength.fair);
    });

    test('rates length plus a digit as strong', () {
      expect(scorePassword('abcdEfgh1'), PasswordStrength.strong);
    });

    test('rates everything at once as very strong', () {
      expect(scorePassword('abcdEfghijkl1!'), PasswordStrength.veryStrong);
    });
  });

  test('every level has a fraction, a label, and a token color', () {
    const tokens = QuarkTokens.dark;
    for (final level in PasswordStrength.values) {
      expect(level.fraction, inInclusiveRange(0.0, 1.0));
      expect(level.color(tokens), isNotNull);
      expect(
        level.label.isEmpty,
        level == PasswordStrength.empty,
        reason: 'only the empty level is unlabeled',
      );
    }
  });
}

void _expectFraction(WidgetTester tester, double fraction) {
  final indicator = tester.widget<LinearProgressIndicator>(
    find.byType(LinearProgressIndicator),
  );
  expect(indicator.value, fraction);
}
