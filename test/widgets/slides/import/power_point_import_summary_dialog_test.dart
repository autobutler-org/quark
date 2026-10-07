import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/import/power_point_import_summary_dialog.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' as tap;

/// What a PowerPoint import left out, shown before the presentation opens
/// (#1171).
void main() {
  test('lists each warning once with the slides it was on', () {
    final groups = PowerPointImportSummaryDialog.grouped(const [
      (slide: 5, message: 'Charts are not imported.'),
      (slide: 0, message: 'Animations and transitions are not imported.'),
      (slide: 2, message: 'Charts are not imported.'),
      (slide: 3, message: '  '),
    ]);
    expect(
      [for (final g in groups) g.message],
      [
        'Charts are not imported.',
        'Animations and transitions are not imported.',
      ],
    );
    expect(
      [for (final g in groups) g.slides],
      [
        [2, 5],
        [0],
      ],
    );
  });

  test('says where a warning applied', () {
    final where = PowerPointImportSummaryDialog.where;
    expect(where([0]), 'Whole presentation');
    expect(where([4]), 'Slide 4');
    expect(where([0, 4]), 'Slide 4');
    expect(where([2, 5]), 'Slides 2 and 5');
    expect(where([1, 2, 9]), 'Slides 1, 2 and 9');
  });

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('shows the summary and closes from its button ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  await PowerPointImportSummaryDialog.show(context, (
                    path: 'Talk.qslide',
                    slides: 1,
                    warnings: const [
                      (slide: 1, message: 'Video and audio are not imported.'),
                    ],
                  ));
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.text('1 kind of content was left out or simplified'),
        findsOneWidget,
      );
      expect(find.textContaining('has 1 slide.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('slides_import_warning_0')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);

      await tester.tap(
        find.byKey(const ValueKey('slides_import_summary_open')),
      );
      await tester.pumpAndSettle();
      expect(closed, isTrue);
    });
  }
}
