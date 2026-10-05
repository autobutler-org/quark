import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/present/slide_present_stage.dart';
import 'package:quark/widgets/slides/present/slide_presenter_view.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' as tap;

/// A presentation is shown in its theme (#1163), on the stage and in the
/// presenter view's next-slide preview.
void main() {
  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('draws the slides in the deck\'s theme ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
          home: Scaffold(
            body: SlidePresenterView(
              stage: SlidePresentStage(
                slide: Slide(id: 's1'),
                size: SlideSize.widescreen,
                label: 'Slide 1 of 2',
                theme: SlideThemes.dark,
              ),
              next: Slide(id: 's2'),
              size: SlideSize.widescreen,
              notes: '',
              elapsed: ValueNotifier(Duration.zero),
              theme: SlideThemes.dark,
            ),
          ),
        ),
      );
      final canvases = tester.widgetList<SlideCanvas>(find.byType(SlideCanvas));
      expect(canvases, hasLength(2));
      expect(canvases.map((c) => c.theme), everyElement(SlideThemes.dark));
      expect(tester.takeException(), isNull);
    });
  }
}
