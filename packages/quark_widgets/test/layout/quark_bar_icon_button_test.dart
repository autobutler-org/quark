import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  const key = ValueKey('select');

  Widget button({
    VoidCallback? onPressed,
    bool isBusy = false,
    bool destructive = false,
  }) => Center(
    child: QuarkBarIconButton(
      key: key,
      icon: QuarkIcons.check_circle_outline,
      tooltip: 'Select',
      onPressed: onPressed,
      isBusy: isBusy,
      destructive: destructive,
    ),
  );

  RenderParagraph glyph(WidgetTester tester) => tester.renderObject(
    find.descendant(of: find.byKey(key), matching: find.byType(RichText)),
  );

  testBothViewports('runs its action and explains itself', (
    tester,
    size,
  ) async {
    var presses = 0;
    await pumpAt(tester, button(onPressed: () => presses++), size: size);

    expect(find.byTooltip('Select'), findsOneWidget);
    await tester.tap(find.byKey(key));
    await tester.pump();

    expect(presses, 1);
  });

  testBothViewports('is one fixed square with an 18px glyph', (
    tester,
    size,
  ) async {
    await pumpAt(tester, button(onPressed: () {}), size: size);

    expect(
      tester.getSize(find.byKey(key)),
      const Size.square(QuarkBarIconButton.size),
    );
    expect(glyph(tester).text.style!.fontSize, QuarkBarIconButton.glyphSize);
    expect(tester.takeException(), isNull);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: draws from the tokens', (tester) async {
      await pumpAt(tester, button(onPressed: () {}), brightness: brightness);

      expect(glyph(tester).text.style!.color, tokens.secondaryForeground);
      final material = tester.widget<Material>(
        find.descendant(of: find.byKey(key), matching: find.byType(Material)),
      );
      expect(material.color, tokens.input);
      final shape = material.shape! as RoundedRectangleBorder;
      expect(shape.side.color, tokens.border);
      expect(shape.borderRadius, BorderRadius.circular(tokens.radiusMd));
    });
  }

  testWidgets('a destructive action wears the error token', (tester) async {
    await pumpAt(tester, button(onPressed: () {}, destructive: true));

    expect(glyph(tester).text.style!.color, QuarkTokens.dark.error);
  });

  testWidgets('is disabled, not hidden, without a callback', (tester) async {
    await pumpAt(tester, button(), size: narrowViewport);

    expect(find.byKey(key), findsOneWidget);
    expect(glyph(tester).text.style!.color, QuarkTokens.dark.mutedForeground);
  });

  testBothViewports('spins and refuses taps while busy', (tester, size) async {
    var presses = 0;
    await pumpAt(
      tester,
      button(onPressed: () => presses++, isBusy: true),
      size: size,
    );

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.byIcon(QuarkIcons.check_circle_outline), findsNothing);

    await tester.tap(find.byKey(key), warnIfMissed: false);
    await tester.pump();

    expect(presses, 0);
  });
}
