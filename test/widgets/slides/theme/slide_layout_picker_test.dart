import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/theme/slide_layout_picker.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' as tap;
import '../../../support/text_scale.dart';

/// The layout picker (#1163): a preview of each layout's placeholders in
/// the deck's theme, the slide's marked, and Reset slide to layout.
void main() {
  late List<String> events;

  setUp(() => events = []);

  Future<void> pump(WidgetTester tester, {bool reset = true}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 248,
                child: SlideLayoutPicker(
                  layouts: SlideMaster.standard.layouts,
                  currentLayoutId: SlideLayout.title.id,
                  size: SlideSize.widescreen,
                  theme: SlideThemes.cool,
                  onSelected: (id) => events.add('layout $id'),
                  onReset: reset ? () => events.add('reset') : null,
                ),
              ),
            ),
          ),
        ),
      );

  Finder card(String id) => find.byKey(ValueKey('slide_layout_$id'));

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('marks the slide\'s layout, picks and resets ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      await pump(tester);

      for (final layout in SlideMaster.standard.layouts) {
        final canvas = tester.widget<SlideCanvas>(
          find.descendant(
            of: card(layout.id),
            matching: find.byType(SlideCanvas),
          ),
        );
        expect(canvas.theme, SlideThemes.cool);
        expect(canvas.slide!.elements, hasLength(layout.placeholders.length));
      }
      expect(
        tester.getSemantics(card('title')),
        isSemantics(label: 'Title slide', isSelected: true, isButton: true),
      );

      await tester.tap(card('twoContent'));
      await tester.tap(find.byKey(const ValueKey('slide_layout_reset')));
      expect(events, ['layout twoContent', 'reset']);
      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);
    });
  }

  testWidgets('leaves reset out without a handler', (tester) async {
    await pump(tester, reset: false);
    expect(find.byKey(const ValueKey('slide_layout_reset')), findsNothing);
  });

  testLargeText('the cards fit', (tester, size) async {
    await pump(tester);
    expect(tester.takeException(), isNull);
  });
}
