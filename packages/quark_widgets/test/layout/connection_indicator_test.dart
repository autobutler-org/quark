import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The app bar's local, remote or offline tile (#1880): one glyph and one
/// token color per state, the caller's label as its tooltip, and no tap
/// target.
void main() {
  const cases = [
    (ConnectionMode.local, QuarkIcons.home_rounded, 'Home label'),
    (ConnectionMode.remote, QuarkIcons.cloud_done_outlined, 'Remote label'),
    (ConnectionMode.offline, QuarkIcons.cloud_off_outlined, 'Offline label'),
  ];

  for (final (mode, icon, label) in cases) {
    testBothViewports('${mode.name}: shows its glyph and the caller\'s label', (
      tester,
      size,
    ) async {
      await pumpAt(
        tester,
        ConnectionIndicator(mode: mode, label: label),
        size: size,
      );
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('connection_indicator')),
        findsOneWidget,
      );
      expect(find.byIcon(icon), findsOneWidget);
      expect(find.byTooltip(label), findsOneWidget);
      expect(find.bySemanticsLabel(label), findsOneWidget);
    });
  }

  testBothViewports('survives a long label', (tester, size) async {
    await pumpAt(
      tester,
      ConnectionIndicator(mode: ConnectionMode.local, label: 'Home ' * 60),
      size: size,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('is a status, not a button', (tester) async {
    await pumpAt(
      tester,
      const ConnectionIndicator(mode: ConnectionMode.remote, label: 'Remote'),
    );
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(InkWell), findsNothing);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: colors come from the tokens', (tester) async {
      for (final (mode, color) in [
        (ConnectionMode.local, tokens.success),
        (ConnectionMode.remote, tokens.primary),
        (ConnectionMode.offline, tokens.warning),
      ]) {
        await pumpAt(
          tester,
          ConnectionIndicator(mode: mode, label: mode.name),
          brightness: brightness,
        );
        expect(tester.widget<Icon>(find.byType(Icon)).color, color);
        final box = tester.widget<Container>(
          find.byKey(const ValueKey('connection_indicator')),
        );
        final decoration = box.decoration! as BoxDecoration;
        expect(decoration.color, tokens.input);
        expect(decoration.border, Border.all(color: tokens.border));
      }
    });
  }
}
