import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/theme/slide_theme_picker.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' as tap;
import '../../../support/text_scale.dart';

/// The theme picker (#1163): a live preview per built-in theme, the
/// current one marked, and a call to action for a deck with no theme.
void main() {
  late List<SlideTheme> picked;

  setUp(() => picked = []);

  Future<void> pump(WidgetTester tester, {SlideTheme? current}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 248,
                child: SlideThemePicker(
                  themes: SlideThemes.all,
                  current: current,
                  size: SlideSize.widescreen,
                  onSelected: picked.add,
                ),
              ),
            ),
          ),
        ),
      );

  Finder card(String id) => find.byKey(ValueKey('slide_theme_$id'));

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('marks the current theme and picks another ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      await pump(tester, current: SlideThemes.dark);

      for (final theme in SlideThemes.all) {
        expect(card(theme.id), findsOneWidget);
        final canvas = tester.widget<SlideCanvas>(
          find.descendant(
            of: card(theme.id),
            matching: find.byType(SlideCanvas),
          ),
        );
        expect(canvas.theme, theme, reason: 'previewed in its own theme');
      }
      expect(
        tester.getSemantics(card('dark')),
        isSemantics(label: 'Dark', isSelected: true, isButton: true),
      );
      expect(
        tester.getSemantics(card('warm')),
        isSemantics(label: 'Warm', isSelected: false, isButton: true),
      );
      expect(find.byKey(const ValueKey('slide_theme_none')), findsNothing);

      await tester.tap(card('warm'));
      expect(picked, [SlideThemes.warm]);
      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);
    });
  }

  testWidgets('a deck with no theme says so and applies one', (tester) async {
    await pump(tester);
    expect(find.text('No theme'), findsOneWidget);
    expect(
      tester.getSemantics(card('light')),
      isSemantics(label: 'Light', isSelected: false, isButton: true),
    );
    await tester.tap(find.byKey(const ValueKey('slide_theme_apply')));
    expect(picked, [SlideThemes.all.first]);
  });

  testLargeText('the cards and note fit', (tester, size) async {
    await pump(tester);
    expect(tester.takeException(), isNull);
  });
}
