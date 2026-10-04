import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/pages/slide_editor_page.dart';
import 'package:quark/widgets/slides/slide_panel.dart';
import 'package:quark/widgets/slides/slide_stage.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/tap_target_guidelines.dart' as tap;
import '../support/text_scale.dart';

/// The slide editor (#1161): the slide panel's add, duplicate, delete and
/// reorder, undo and redo, and the save state, on a phone and a desktop.
void main() {
  late List<Presentation> saved;
  late Object? saveFailure;
  late Object? loadFailure;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    saved = [];
    saveFailure = null;
    loadFailure = null;
  });

  Presentation deck(int count) => Presentation(
    title: 'Deck',
    slides: [
      for (var i = 1; i <= count; i++)
        Slide(
          id: 's$i',
          elements: [
            TextBox(
              id: 't$i',
              frame: ElementFrame(x: 100, y: 100, width: 1700, height: 300),
              paragraphs: [TextParagraph.plain('Slide text $i')],
            ),
          ],
        ),
    ],
  );

  Future<SlideEditorController> pumpEditor(
    WidgetTester tester, {
    int slides = 2,
  }) async {
    var next = 0;
    final controller = SlideEditorController(
      filePath: 'talks/Deck.qslide',
      loadPresentation: (path, {serial}) async {
        final failure = loadFailure;
        if (failure != null) throw failure;
        return deck(slides);
      },
      savePresentation: (path, p, {serial}) async {
        final failure = saveFailure;
        if (failure != null) throw failure;
        saved.add(p);
      },
      newId: () => 'n${next++}',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: SlideEditorPage(
          filePath: 'talks/Deck.qslide',
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  /// Lets the autosave an edit started run, so no timer outlives the test.
  Future<void> letAutosaveRun(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  Finder thumb(String id) => find.byKey(ValueKey('slide_thumb_$id'));

  Future<void> openMenuAndTap(
    WidgetTester tester,
    String slideId,
    String row,
  ) async {
    await tester.tap(find.byKey(ValueKey('slide_menu_$slideId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('${row}_$slideId')));
    await tester.pumpAndSettle();
  }

  for (final (name, size, axis) in [
    ('narrow', tap.narrowViewport, Axis.horizontal),
    ('wide', tap.wideViewport, Axis.vertical),
  ]) {
    testWidgets('shows the panel and the selected slide ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      await pumpEditor(tester);
      expect(find.text('Deck'), findsOneWidget);
      expect(tester.widget<SlidePanel>(find.byType(SlidePanel)).axis, axis);
      expect(thumb('s1'), findsOneWidget);
      expect(thumb('s2'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('slide_editor_stage')),
          matching: find.byType(SlideStage),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Slide 1 of 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);
    });

    testWidgets('adds, duplicates and deletes slides, with undo ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      final c = await pumpEditor(tester);

      await tester.tap(find.byKey(const ValueKey('slide_panel_add')));
      await tester.pumpAndSettle();
      expect([for (final s in c.slides) s.id], ['s1', 'n0', 's2']);
      expect(c.selectedSlideId, 'n0');

      await openMenuAndTap(tester, 's1', 'slide_duplicate');
      expect([for (final s in c.slides) s.id], ['s1', 'n1', 'n0', 's2']);

      await openMenuAndTap(tester, 'n1', 'slide_delete');
      expect([for (final s in c.slides) s.id], ['s1', 'n0', 's2']);

      await tester.tap(find.byKey(const ValueKey('slide_editor_undo')));
      await tester.pumpAndSettle();
      expect([for (final s in c.slides) s.id], ['s1', 'n1', 'n0', 's2']);
      await tester.tap(find.byKey(const ValueKey('slide_editor_redo')));
      await tester.pumpAndSettle();
      expect([for (final s in c.slides) s.id], ['s1', 'n0', 's2']);
      expect(tester.takeException(), isNull);
      await letAutosaveRun(tester);
    });
  }

  testWidgets('tapping a thumbnail selects it', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    final c = await pumpEditor(tester);
    await tester.tap(thumb('s2'));
    await tester.pumpAndSettle();
    expect(c.selectedSlideId, 's2');
    expect(find.bySemanticsLabel('Slide 2 of 2'), findsOneWidget);
  });

  testWidgets('a right-click opens the slide menu and moves a slide', (
    tester,
  ) async {
    tap.setViewport(tester, tap.wideViewport);
    final c = await pumpEditor(tester, slides: 3);
    await tester.tapAt(
      tester.getCenter(thumb('s1')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slide_move_later_s1')));
    await tester.pumpAndSettle();
    expect([for (final s in c.slides) s.id], ['s2', 's1', 's3']);
    await letAutosaveRun(tester);
  });

  testWidgets('a slide is dragged to a new place', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    final c = await pumpEditor(tester, slides: 3);
    final from = tester.getCenter(thumb('s1'));
    final below = tester.getCenter(thumb('s3'));
    final gesture = await tester.startGesture(from);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    // In steps, as a finger moves: the list reorders as the drag passes each
    // slide.
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(
        Offset.lerp(from, below + const Offset(0, 80), i / 10)!,
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect([for (final s in c.slides) s.id], ['s2', 's3', 's1']);
    await letAutosaveRun(tester);
  });

  testWidgets('the last slide cannot be deleted', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    final c = await pumpEditor(tester, slides: 1);
    await tester.tap(find.byKey(const ValueKey('slide_menu_s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slide_delete_s1')));
    await tester.pumpAndSettle();
    expect(c.slides, hasLength(1));
  });

  testWidgets('saves after a pause and says so', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    await pumpEditor(tester);
    expect(find.text('Saved'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('slide_panel_add')));
    await tester.pump();
    expect(find.text('Save'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('a failed save is reported and can be retried', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    await pumpEditor(tester);
    saveFailure = Exception('offline');
    await tester.tap(find.byKey(const ValueKey('slide_panel_add')));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text("Couldn't save the presentation."), findsOneWidget);
    expect(find.text('Retry save'), findsOneWidget);

    saveFailure = null;
    await tester.tap(find.byKey(const ValueKey('slide_editor_save')));
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('a failed load says so and retries', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    loadFailure = Exception('boom');
    await pumpEditor(tester);
    expect(find.text("Couldn't open the presentation."), findsOneWidget);
    loadFailure = null;
    await tester.tap(find.byKey(const ValueKey('slides_retry')));
    await tester.pumpAndSettle();
    expect(thumb('s1'), findsOneWidget);
  });

  testLargeText('the editor fits', (tester, size) async {
    await pumpEditor(tester);
    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
  });
}
