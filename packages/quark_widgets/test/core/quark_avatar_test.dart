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

  test('gives one id the same color every time', () {
    expect(QuarkAvatar.colorFor('ada'), QuarkAvatar.colorFor('ada'));
    expect(QuarkAvatar.colorFor('ada'), isNot(QuarkAvatar.colorFor('bob')));
  });

  test('the initials are legible on every color an id can land on', () {
    final base = HSLColor.fromColor(QuarkAvatar.baseColor);
    for (var hue = 0.0; hue < 360; hue++) {
      final color = base.withHue(hue).toColor();
      expect(
        contrastRatio(QuarkAvatar.initialsColorOn(color), color),
        greaterThanOrEqualTo(4.5),
        reason: 'hue $hue',
      );
    }
  });

  // #2740: a person's color is theirs. It used to be a rotation of the
  // primary token, so it would have moved with the theme color and the mode.
  for (final (label, theme) in [
    ('dark', QuarkTheme.dark()),
    ('light', QuarkTheme.light()),
    ('another theme color', QuarkTheme.dark(themeColor: QuarkThemeColor.pink)),
  ]) {
    testWidgets('$label: the fallback color is the same', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: QuarkAvatar(id: 'u1', name: 'Ada'),
          ),
        ),
      );

      final box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(const ValueKey('avatar_u1')),
          matching: find.byType(DecoratedBox),
        ),
      );
      final color = QuarkAvatar.colorFor('u1');
      expect((box.decoration as BoxDecoration).color, color);
      expect(
        tester.widget<Text>(find.text('A')).style!.color,
        QuarkAvatar.initialsColorOn(color),
      );
    });
  }

  testWidgets('names itself for screen readers', (tester) async {
    await pumpAt(tester, const QuarkAvatar(id: 'u1', name: 'Ada Lovelace'));
    expect(find.bySemanticsLabel('Ada Lovelace'), findsOneWidget);
  });
}
