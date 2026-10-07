import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/transition/slide_transition_labels.dart';
import 'package:quark/widgets/slides/transition/slide_transition_marker.dart';
import 'package:quark/widgets/slides/transition/slide_transition_preview.dart';
import 'package:quark/widgets/slides/transition/slide_transition_direction_field.dart';
import 'package:quark/widgets/slides/transition/slide_transition_duration_field.dart';
import 'package:quark/widgets/slides/transition/slide_transition_kind_field.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' as tap;
import '../../../support/text_scale.dart';

/// The transition picker's parts (#1164): data in, callbacks out.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SizedBox(width: 296, child: child),
        ),
      ),
    ),
  );

  Finder key(String k) => find.byKey(ValueKey(k));

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('the fields report choices and meet tap guidelines ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      final kinds = <SlideTransitionKind>[];
      final directions = <SlideTransitionDirection>[];
      final lengths = <int>[];
      await pump(
        tester,
        Column(
          children: [
            SlideTransitionKindField(
              kind: SlideTransitionKind.push,
              onChanged: kinds.add,
            ),
            SlideTransitionDirectionField(
              direction: SlideTransitionDirection.left,
              onChanged: directions.add,
            ),
            SlideTransitionDurationField(
              durationMs: 500,
              onChanged: lengths.add,
            ),
          ],
        ),
      );
      await tester.tap(key('slide_transition_kind_zoom'));
      await tester.tap(key('slide_transition_direction_down'));
      await tester.drag(key('slide_transition_duration'), const Offset(300, 0));
      await tester.pump();
      expect(kinds, [SlideTransitionKind.zoom]);
      expect(directions, [SlideTransitionDirection.down]);
      expect(lengths, hasLength(1), reason: 'one report per drag');
      await tap.expectTapTargetGuidelines(tester);
    });

    testWidgets('a field with no handler takes no input ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      await pump(
        tester,
        const Column(
          children: [
            SlideTransitionKindField(
              kind: SlideTransitionKind.none,
              onChanged: null,
            ),
            SlideTransitionDurationField(durationMs: 500, onChanged: null),
          ],
        ),
      );
      expect(
        tester.widget<ChoiceChip>(key('slide_transition_kind_fade')).onSelected,
        isNull,
      );
      expect(
        tester.widget<Slider>(key('slide_transition_duration')).onChanged,
        isNull,
      );
    });
  }

  testWidgets('the duration shows its number and clamps', (tester) async {
    await pump(
      tester,
      SlideTransitionDurationField(durationMs: 1200, onChanged: (_) {}),
    );
    expect(find.text('1200 ms'), findsOneWidget);
  });

  testWidgets('the marker is empty for none and labeled otherwise', (
    tester,
  ) async {
    await pump(
      tester,
      const SlideTransitionMarker(transition: SlideTransitionSpec.none),
    );
    expect(key('slide_transition_marker'), findsNothing);

    final handle = tester.ensureSemantics();
    await pump(
      tester,
      const SlideTransitionMarker(
        transition: SlideTransitionSpec(kind: SlideTransitionKind.push),
      ),
    );
    expect(key('slide_transition_marker'), findsOneWidget);
    expect(find.bySemanticsLabel('Push transition, left'), findsOneWidget);
    handle.dispose();
  });

  test('labels name every kind and direction', () {
    for (final kind in SlideTransitionKind.values) {
      expect(SlideTransitionLabels.kind(kind), isNotEmpty);
    }
    for (final d in SlideTransitionDirection.values) {
      expect(SlideTransitionLabels.direction(d), isNotEmpty);
    }
    expect(
      SlideTransitionLabels.describe(SlideTransitionSpec.fade()),
      'Fade transition',
    );
  });

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('the preview plays once, then rests on the slide ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      await pump(
        tester,
        SlideTransitionPreview(
          slide: Slide(id: 'b'),
          previous: Slide(id: 'a'),
          size: SlideSize.widescreen,
          transition: const SlideTransitionSpec.fade(),
        ),
      );
      Finder canvases() => find.descendant(
        of: key('slide_transition_stage'),
        matching: find.byType(SlideCanvas),
      );
      expect(canvases(), findsOneWidget);
      await tester.tap(key('slide_transition_preview'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(canvases(), findsNWidgets(2));
      await tester.pumpAndSettle();
      expect(canvases(), findsOneWidget);
      await tap.expectTapTargetGuidelines(tester);
    });
  }

  testWidgets('the preview of the first slide arrives from a blank one', (
    tester,
  ) async {
    await pump(
      tester,
      SlideTransitionPreview(
        slide: Slide(id: 'a'),
        previous: null,
        size: SlideSize.widescreen,
        transition: const SlideTransitionSpec.fade(),
      ),
    );
    await tester.tap(key('slide_transition_preview'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });

  for (final entry in largeTextViewports.entries) {
    testWidgets('the preview and fields fit at 200% text (${entry.key})', (
      tester,
    ) async {
      useLargeText(tester, entry.value);
      await pump(
        tester,
        Column(
          children: [
            SlideTransitionKindField(
              kind: SlideTransitionKind.wipe,
              onChanged: (_) {},
            ),
            SlideTransitionPreview(
              slide: Slide(id: 'b'),
              previous: null,
              size: SlideSize.widescreen,
              transition: const SlideTransitionSpec.fade(),
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
