import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  for (final (mode, icon, tooltip, next) in [
    (
      ThemeMode.system,
      QuarkIcons.brightness_auto_rounded,
      'Theme matches your device. Switch to light',
      ThemeMode.light,
    ),
    (
      ThemeMode.light,
      QuarkIcons.light_mode_rounded,
      'Theme is light. Switch to dark',
      ThemeMode.dark,
    ),
    (
      ThemeMode.dark,
      QuarkIcons.dark_mode_rounded,
      'Theme is dark. Switch to match your device',
      ThemeMode.system,
    ),
  ]) {
    testBothViewports('shows ${mode.name} and moves on to ${next.name}', (
      tester,
      size,
    ) async {
      final chosen = <ThemeMode>[];
      await pumpAt(
        tester,
        ThemeToggleButton(mode: mode, onChanged: chosen.add),
        size: size,
      );

      expect(find.byIcon(icon), findsOneWidget);
      expect(find.byTooltip(tooltip), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('theme_toggle')));
      await tester.pump();

      expect(chosen, [next]);
    });
  }

  testBothViewports('meets the tap target guidelines', (tester, size) async {
    await pumpAt(
      tester,
      Center(
        child: ThemeToggleButton(mode: ThemeMode.light, onChanged: (_) {}),
      ),
      size: size,
    );

    await expectTapTargetGuidelines(tester);
  });
}
