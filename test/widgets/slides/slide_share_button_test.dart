import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/slide_share_button.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart' as tap;

/// The editor bar's Share action (#1170).
void main() {
  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('a tap calls back, and it is labeled ($name)', (tester) async {
      tap.setViewport(tester, size);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
          home: Scaffold(
            appBar: AppBar(
              actions: [SlideShareButton(onPressed: () => taps++)],
            ),
          ),
        ),
      );
      expect(find.byTooltip(SlideShareButton.label), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('slide_editor_share')));
      expect(taps, 1);
      await tap.expectTapTargetGuidelines(tester);
    });
  }

  testWidgets('with no callback it is disabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: const Scaffold(
          body: Center(child: SlideShareButton(onPressed: null)),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('slide_editor_share')), findsOneWidget);
  });
}
