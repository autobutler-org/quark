import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The avatar drawn beside a person's name (#2419): the caller's picture when
/// it has one, and the person's initials on a color of their own when not.
void main() {
  testBothViewports('draws the initials without a picture', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const QuarkAvatar(id: 'u1', name: 'Ada Lovelace'),
      size: size,
    );

    expect(find.byKey(const ValueKey('avatar_u1')), findsOneWidget);
    expect(find.text('AL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('draws the picture the builder hands it, at its size', (
    tester,
    size,
  ) async {
    final sizes = <double>[];
    await pumpAt(
      tester,
      QuarkAvatar(
        id: 'u1',
        name: 'Ada Lovelace',
        size: 48,
        imageBuilder: (context, size) {
          sizes.add(size);
          return const SizedBox(key: ValueKey('picture'));
        },
      ),
      size: size,
    );

    expect(find.byKey(const ValueKey('picture')), findsOneWidget);
    expect(find.text('AL'), findsNothing);
    expect(sizes, [48]);
    expect(
      tester.getSize(find.byKey(const ValueKey('avatar_u1'))),
      const Size(48, 48),
    );
  });

  test('takes initials from the first and last words', () {
    expect(QuarkAvatar.initialsOf('Ada Lovelace'), 'AL');
    expect(QuarkAvatar.initialsOf('grace brewster hopper'), 'GH');
    expect(QuarkAvatar.initialsOf('bob'), 'B');
    expect(QuarkAvatar.initialsOf('jane.doe'), 'JD');
    expect(QuarkAvatar.initialsOf('   '), '?');
  });

  test('gives one id the same color every time and follows the tokens', () {
    const tokens = QuarkTokens.dark;
    expect(
      QuarkAvatar.colorFor('ada', tokens),
      QuarkAvatar.colorFor('ada', tokens),
    );
    expect(
      QuarkAvatar.colorFor('ada', tokens),
      isNot(QuarkAvatar.colorFor('bob', tokens)),
    );
    final red = tokens.copyWith(primary: const Color(0xFFFF0000));
    expect(
      QuarkAvatar.colorFor('ada', red),
      isNot(QuarkAvatar.colorFor('ada', tokens)),
    );
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: the fallback color comes from the tokens', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const QuarkAvatar(id: 'u1', name: 'Ada'),
        brightness: brightness,
      );

      final box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(const ValueKey('avatar_u1')),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(
        (box.decoration as BoxDecoration).color,
        QuarkAvatar.colorFor('u1', tokens),
      );
    });
  }

  testWidgets('names itself for screen readers', (tester) async {
    await pumpAt(tester, const QuarkAvatar(id: 'u1', name: 'Ada Lovelace'));
    expect(find.bySemanticsLabel('Ada Lovelace'), findsOneWidget);
  });
}
