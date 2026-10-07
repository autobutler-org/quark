import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/pages/slide_editor_page.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/router.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_group.dart';
import 'package:quark/widgets/slides/slide_panel.dart';
import 'package:quark/widgets/slides/export/slide_export_button.dart';
import 'package:quark/widgets/slides/slide_share_button.dart';
import 'package:quark/widgets/slides/slide_view_only_badge.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/tap_target_guidelines.dart' as tap;
import '../support/text_scale.dart';

/// The slide editor (#1161, #1153): the slide panel's add, duplicate, delete
/// and reorder, the canvas editing the selected slide, zoom, undo and redo
/// from the bar and the keyboard, and the save state, on a phone and a
/// desktop.
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
    bool readOnly = false,
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
      readOnly: readOnly,
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
          matching: find.byType(SlideCanvas),
        ),
        findsOneWidget,
      );
      // The thumbnails draw with the read-only canvas, behind a repaint
      // boundary and with no input.
      final thumbCanvas = find.descendant(
        of: thumb('s2'),
        matching: find.byType(SlideCanvas),
      );
      expect(tester.widget<SlideCanvas>(thumbCanvas).readOnly, isTrue);
      expect(
        find.ancestor(of: thumbCanvas, matching: find.byType(RepaintBoundary)),
        findsWidgets,
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

  /// An element on the editing canvas, not its copy in a thumbnail.
  Finder element(String id) => find.descendant(
    of: find.byKey(const ValueKey('slide_editor_canvas')),
    matching: find.byKey(ValueKey('slide_element_$id')),
  );

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets(
      'a canvas edit undoes from the keyboard and autosaves ($name)',
      (tester) async {
        tap.setViewport(tester, size);
        final c = await pumpEditor(tester);
        await tester.tap(element('t1'));
        await tester.pump();
        expect(c.selectedElementIds, {'t1'});

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        double x() => c.slides.first.elements.single.frame.x;
        expect(x(), 101);
        expect(c.saveState, SlideSaveState.dirty);
        // The panel's thumbnail draws the edit.
        final thumbCanvas = tester.widget<SlideCanvas>(
          find.descendant(of: thumb('s1'), matching: find.byType(SlideCanvas)),
        );
        expect(thumbCanvas.slide!.elements.single.frame.x, 101);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        expect(x(), 100);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        expect(x(), 101);
        // Cmd works as well as Ctrl.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        expect(x(), 100);
        await tester.pump();
        expect(c.canRedo, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await letAutosaveRun(tester);
        expect(saved.last.slides.first.elements.single.frame.y, 101);
        expect(c.saveState, SlideSaveState.saved);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('the canvas selection empties on another slide', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    final c = await pumpEditor(tester);
    await tester.tap(element('t1'));
    await tester.pump();
    expect(c.selectedElementIds, {'t1'});
    await tester.tap(thumb('s2'));
    await tester.pumpAndSettle();
    expect(c.selectedElementIds, isEmpty);
    expect(element('t2'), findsOneWidget);
  });

  testWidgets('the arrow keys step through the slide panel', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    final c = await pumpEditor(tester, slides: 3);
    await tester.tap(thumb('s1'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(c.selectedSlideId, 's2');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(c.selectedSlideId, 's3');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(c.selectedSlideId, 's2');
    // Nothing moved on the canvas: the keys went to the panel.
    expect(c.isDirty, isFalse);
  });

  testWidgets('the bar zooms the canvas and fits it again', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    final c = await pumpEditor(tester);
    expect(find.text('100%'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('slide_zoom_in')));
    await tester.pump();
    expect(c.zoom, 1.25);
    expect(find.text('125%'), findsOneWidget);
    expect(
      tester
          .widget<SlideCanvas>(
            find.byKey(const ValueKey('slide_editor_canvas')),
          )
          .zoom,
      1.25,
    );
    await tester.tap(find.byKey(const ValueKey('slide_zoom_out')));
    await tester.tap(find.byKey(const ValueKey('slide_zoom_out')));
    await tester.pump();
    expect(c.zoom, 0.75);
    await tester.tap(find.byKey(const ValueKey('slide_zoom_fit')));
    await tester.pump();
    expect(c.zoom, 1);
    expect(c.isDirty, isFalse);
  });

  testWidgets('a phone zooms from the Format menu\'s Zoom', (tester) async {
    tap.setViewport(tester, tap.narrowViewport);
    final c = await pumpEditor(tester);
    expect(find.byKey(const ValueKey('slide_zoom_in')), findsNothing);
    expect(find.byKey(const ValueKey('app_bar_bottom_menu')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('slide_format_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slide_zoom_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slide_menu_zoom_in')));
    await tester.pumpAndSettle();
    expect(c.zoom, 1.25);
    expect(find.text('Slide 1 of 2'), findsOneWidget);
  });

  group('speaker notes (#1166)', () {
    Finder field() => find.byKey(const ValueKey('slide_notes_field'));

    for (final (name, size) in [
      ('narrow', tap.narrowViewport),
      ('wide', tap.wideViewport),
    ]) {
      testWidgets('typed under the canvas, undone and autosaved ($name)', (
        tester,
      ) async {
        tap.setViewport(tester, size);
        final c = await pumpEditor(tester);
        expect(field(), findsNothing, reason: 'the panel starts closed');
        await tester.tap(find.byKey(const ValueKey('slide_notes_toggle')));
        await tester.pumpAndSettle();
        expect(field(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tap.expectTapTargetGuidelines(tester);

        await tester.enterText(field(), 'Open with the story');
        await tester.pump(SlideEditorController.notesDelay);
        expect(c.slides.first.notes, 'Open with the story');
        expect(c.saveState, SlideSaveState.dirty);
        await letAutosaveRun(tester);
        expect(saved.last.slides.first.notes, 'Open with the story');

        // Another slide's notes replace the field's text.
        await tester.tap(thumb('s2'));
        await tester.pumpAndSettle();
        expect(find.text('Open with the story'), findsNothing);

        await tester.tap(find.byKey(const ValueKey('slide_editor_undo')));
        await tester.pumpAndSettle();
        await tester.tap(thumb('s1'));
        await tester.pumpAndSettle();
        expect(c.slides.first.notes, '');
        expect(tester.widget<TextField>(field()).controller!.text, '');
        await letAutosaveRun(tester);
      });
    }

    testLargeText('the open notes panel fits', (tester, size) async {
      final c = await pumpEditor(tester);
      c.toggleNotes();
      await tester.pumpAndSettle();
      expect(field(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('presenting (#1165)', () {
    Future<(SlideEditorController, GoRouter)> pumpRouted(
      WidgetTester tester,
    ) async {
      final controller = SlideEditorController(
        filePath: 'talks/Deck.qslide',
        loadPresentation: (path, {serial}) async => deck(3),
        savePresentation: (path, p, {serial}) async => saved.add(p),
      );
      addTearDown(controller.dispose);
      final router = GoRouter(
        initialLocation: AppRoutes.slideFile('talks/Deck.qslide'),
        routes: [
          slidePresentRoute(
            builder: (filePath, serial, startIndex, initial) => Text(
              'present $filePath from $startIndex '
              '${initial?.slides.first.notes}',
            ),
          ),
          GoRoute(
            path: '${AppRoutes.slides}/:path(.*)',
            builder: (_, state) => SlideEditorPage(
              filePath: state.pathParameters['path']!,
              controller: controller,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();
      return (controller, router);
    }

    testWidgets('Present starts at the first slide with unsaved edits', (
      tester,
    ) async {
      tap.setViewport(tester, tap.wideViewport);
      final (c, _) = await pumpRouted(tester);
      c.selectSlide('s2');
      c.selectSlide('s1');
      c.editNotes('Fresh');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('slide_editor_present')));
      await tester.pumpAndSettle();
      expect(
        find.text('present talks/Deck.qslide from 0 Fresh'),
        findsOneWidget,
      );
      expect(
        saved.last.slides.first.notes,
        'Fresh',
        reason: 'saved on the way',
      );
    });

    testWidgets('a slide\'s menu presents from that slide', (tester) async {
      tap.setViewport(tester, tap.wideViewport);
      await pumpRouted(tester);
      await tester.tap(find.byKey(const ValueKey('slide_menu_s3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slide_present_s3')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('present talks/Deck.qslide from 2'),
        findsOneWidget,
      );
    });
  });

  group('toolbar, properties and pictures (#1167, #1158)', () {
    Presentation drawn() => Presentation(
      title: 'Deck',
      slides: [
        Slide(
          id: 's1',
          elements: [
            TextBox(
              id: 'text',
              frame: ElementFrame(x: 100, y: 100, width: 1700, height: 300),
              paragraphs: [TextParagraph.plain('Hello')],
            ),
            ShapeElement(
              id: 'shape',
              frame: ElementFrame(x: 200, y: 500, width: 400, height: 300),
              fill: const SlideColor(0xFF3366FF),
            ),
            ImageElement(
              id: 'pic',
              frame: ElementFrame(x: 1000, y: 500, width: 400, height: 300),
              source: 'talks/dog.png',
            ),
          ],
        ),
      ],
    );

    late List<String> uploads;
    late Object? uploadFailure;
    late String? clipboardText;

    Future<SlideEditorController> pumpDrawn(WidgetTester tester) async {
      uploads = [];
      uploadFailure = null;
      clipboardText = null;
      final controller = SlideEditorController(
        clipboard: SlideClipboard(
          read: () async => clipboardText,
          write: (text) async => clipboardText = text,
        ),
        filePath: 'talks/Deck.qslide',
        loadPresentation: (_, {serial}) async => drawn(),
        savePresentation: (_, p, {serial}) async => saved.add(p),
        // A picture never loads in a test; the canvas shows its placeholder.
        mediaUrl: (path, {serial}) => Uri.parse('http://quark.invalid/$path'),
        pickImageFile: () async =>
            (name: 'cat.png', length: 3, bytes: Stream<List<int>>.empty),
        uploadImage:
            (
              path, {
              required name,
              required bytes,
              required length,
              serial,
              onProgress,
            }) async {
              final failure = uploadFailure;
              if (failure != null) throw failure;
              uploads.add(name);
              return (path: 'talks/$name', size: (width: 800.0, height: 400.0));
            },
        readImageSize: (path, {serial}) async => (width: 300.0, height: 300.0),
        listFolder: (path, {serial}) async => [
          FileNode(
            name: 'holiday',
            size: 0,
            isDir: true,
            deviceName: '',
            devicePath: '',
            deviceSerial: '',
            dirPath: '$path/holiday',
          ),
          FileNode(
            name: 'beach.jpg',
            size: 10,
            isDir: false,
            deviceName: '',
            devicePath: '',
            deviceSerial: '',
            dirPath: '$path/beach.jpg',
          ),
          FileNode(
            name: 'notes.txt',
            size: 10,
            isDir: false,
            deviceName: '',
            devicePath: '',
            deviceSerial: '',
            dirPath: '$path/notes.txt',
          ),
        ],
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

    Finder key(String k) => find.byKey(ValueKey(k));

    SlideElement element(SlideEditorController c, String id) =>
        c.selectedSlide!.elements.firstWhere((e) => e.id == id);

    testWidgets('a wide window\'s tool row picks the tool the canvas '
        'draws with', (tester) async {
      tap.setViewport(tester, tap.wideViewport);
      final c = await pumpDrawn(tester);

      expect(key('slide_toolbar'), findsOneWidget);
      expect(key('slide_format_hint'), findsOneWidget);
      await tester.tap(key('slide_tool_text'));
      await tester.pump();
      expect(c.tools.tool, SlideCanvasTool.text);
      await tester.tap(key('slide_tool_shape'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_tool_shape_ellipse'));
      await tester.pumpAndSettle();
      expect(c.tools.tool, const SlideCanvasTool.shape(ShapeKind.ellipse));
      await tester.tap(key('slide_tool_select'));
      await tester.pump();
      expect(c.tools.tool, SlideCanvasTool.select);
    });

    // Switching tools and then the selection in one test trips a semantics
    // assertion in quark_slides' SlideCanvas, which wraps itself in a
    // Semantics only while a drawing tool is active; reported to its owner.
    testWidgets('a wide window\'s format row follows the selection', (
      tester,
    ) async {
      tap.setViewport(tester, tap.wideViewport);
      final c = await pumpDrawn(tester);

      c.selectElements({'text'});
      await tester.pump();
      expect(key(SlideToolbarGroup.text.key), findsOneWidget);
      expect(key(SlideToolbarGroup.shape.key), findsNothing);
      await tester.tap(key('slide_format_bold'));
      await tester.pump();
      final run = (element(c, 'text') as TextBox).paragraphs.single.runs.single;
      expect(run.bold, isTrue);
      expect(c.saveState, SlideSaveState.dirty);
      await tester.tap(key('slide_format_font_larger'));
      await tester.pump();
      expect(c.fontSize, 40);
      expect(find.text('40'), findsOneWidget);

      c.selectElements({'shape'});
      await tester.pump();
      expect(key(SlideToolbarGroup.text.key), findsNothing);
      expect(key(SlideToolbarGroup.shape.key), findsOneWidget);
      await tester.tap(key('slide_fill'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_fill_none'));
      await tester.pumpAndSettle();
      expect((element(c, 'shape') as ShapeElement).fill, isNull);
      await tester.tap(key('slide_arrange'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_arrange_toFront'));
      await tester.pumpAndSettle();
      expect(c.selectedSlide!.elements.last.id, 'shape');
      await tester.tap(key('slide_delete'));
      await tester.pump();
      expect(
        c.selectedSlide!.elements.map((e) => e.id),
        isNot(contains('shape')),
      );

      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);
      await letAutosaveRun(tester);
    });

    testWidgets('a custom color is typed as hex', (tester) async {
      tap.setViewport(tester, tap.wideViewport);
      final c = await pumpDrawn(tester);
      c.selectElements({'shape'});
      await tester.pump();
      await tester.tap(key('slide_stroke_color'));
      await tester.pumpAndSettle();
      await tester.enterText(key('slide_stroke_color_hex'), '#12ab34');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        (element(c, 'shape') as ShapeElement).stroke?.color,
        const SlideColor(0xFF12AB34),
      );
      await letAutosaveRun(tester);
    });

    testWidgets('the properties panel sets position, size and alt text, '
        'and hides from the toolbar', (tester) async {
      tap.setViewport(tester, tap.wideViewport);
      final c = await pumpDrawn(tester);
      expect(key('slide_properties'), findsOneWidget);
      expect(key('slide_prop_hint'), findsOneWidget);

      c.selectElements({'pic'});
      await tester.pump();
      await tester.enterText(key('slide_prop_x'), '640');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(element(c, 'pic').frame.x, 640);
      await tester.enterText(key('slide_prop_rotation'), '90');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(element(c, 'pic').frame.rotation, 90);

      await tester.enterText(key('slide_prop_alt_text'), 'A dog');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect((element(c, 'pic') as ImageElement).altText, 'A dog');

      c.undo();
      await tester.pump();
      expect((element(c, 'pic') as ImageElement).altText, '');

      await tester.tap(key('slide_properties_toggle'));
      await tester.pump();
      expect(key('slide_properties'), findsNothing);
      expect(c.propertiesOpen, isFalse);
      await letAutosaveRun(tester);
    });

    testWidgets('a picture from this device is uploaded and placed, '
        'and a failure says so', (tester) async {
      tap.setViewport(tester, tap.wideViewport);
      final c = await pumpDrawn(tester);
      await tester.tap(key('slide_tool_image'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_image_device'));
      await tester.pumpAndSettle();

      expect(uploads, ['cat.png']);
      final image = c.selectedSlide!.elements.last as ImageElement;
      expect(image.source, 'talks/cat.png');
      expect(c.selectedElementIds, {image.id});

      uploadFailure = Exception('offline');
      await tester.tap(key('slide_tool_image'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_image_device'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't add the picture."), findsOneWidget);
      await letAutosaveRun(tester);
    });

    testWidgets('a picture on the Quark is picked from its folder', (
      tester,
    ) async {
      tap.setViewport(tester, tap.wideViewport);
      final c = await pumpDrawn(tester);
      await tester.tap(key('slide_tool_image'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_image_quark'));
      await tester.pumpAndSettle();

      expect(key('slide_quark_image_dialog'), findsOneWidget);
      expect(key('slide_quark_image_folder_holiday'), findsOneWidget);
      expect(key('slide_quark_image_file_notes.txt'), findsNothing);
      await tester.tap(key('slide_quark_image_file_beach.jpg'));
      await tester.pumpAndSettle();

      final image = c.selectedSlide!.elements.last as ImageElement;
      expect(image.source, 'talks/beach.jpg');
      expect(image.frame.width, image.frame.height);
      await letAutosaveRun(tester);
    });

    testWidgets('a phone picks a tool from the Insert menu', (tester) async {
      tap.setViewport(tester, tap.narrowViewport);
      final c = await pumpDrawn(tester);
      await tester.tap(key('slide_insert_menu'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_insert_shape'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_tool_shape_star'));
      await tester.pumpAndSettle();
      expect(c.tools.tool, const SlideCanvasTool.shape(ShapeKind.star));
      await tester.tap(key('slide_insert_menu'));
      await tester.pumpAndSettle();
      expect(key('slide_insert_image'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a phone folds the toolbar into Insert and Format menus '
        'in the bar, with Properties in a sheet', (tester) async {
      tap.setViewport(tester, tap.narrowViewport);
      final c = await pumpDrawn(tester);
      expect(key('slide_toolbar'), findsNothing);
      expect(key('slide_properties'), findsNothing);

      c.selectElements({'shape'});
      await tester.pump();
      await tester.tap(key('slide_format_menu'));
      await tester.pumpAndSettle();
      await tester.tap(key(SlideToolbarGroup.clipboard.key));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_duplicate'));
      await tester.pumpAndSettle();
      expect(c.selectedSlide!.elements, hasLength(4));

      await tester.tap(key('slide_format_menu'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_format_properties'));
      await tester.pumpAndSettle();
      expect(key('slide_properties'), findsOneWidget);
      expect(key('slide_prop_x'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await letAutosaveRun(tester);
    });

    testLargeText('the toolbar and panel fit', (tester, size) async {
      final c = await pumpDrawn(tester);
      c.selectElements({'text'});
      await tester.pump();
      expect(tester.takeException(), isNull);
      c.selectElements({'shape'});
      await tester.pump();
      expect(tester.takeException(), isNull);
      c.selectElements({'text', 'shape', 'pic'});
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wide window arranges the selection: group, ungroup, '
        'align, distribute and match size, one undo step each', (tester) async {
      tap.setViewport(tester, tap.wideViewport);
      final c = await pumpDrawn(tester);

      c.selectElements({'shape'});
      await tester.pump();
      expect(key(SlideToolbarGroup.arrange.key), findsOneWidget);
      expect(key('slide_group'), findsNothing);
      expect(key('slide_distribute'), findsNothing);
      expect(key('slide_match_size'), findsNothing);
      // One element lines up with the slide.
      await tester.tap(key('slide_align'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_align_top'));
      await tester.pumpAndSettle();
      expect(element(c, 'shape').frame.y, 0);

      c.selectElements({'shape', 'pic'});
      await tester.pump();
      expect(key('slide_distribute'), findsNothing);
      await tester.tap(key('slide_align'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_align_left'));
      await tester.pumpAndSettle();
      expect(element(c, 'pic').frame.x, 200);
      await tester.tap(key('slide_match_size'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_match_size_height'));
      await tester.pumpAndSettle();
      expect(element(c, 'pic').frame.height, 300);

      await tester.tap(key('slide_group'));
      await tester.pump();
      final group = c.singleSelected;
      expect(group, isA<GroupElement>());
      expect(key('slide_group'), findsNothing);
      await tester.tap(key('slide_ungroup'));
      await tester.pump();
      expect(c.selectedElementIds, {'shape', 'pic'});

      c.selectElements({'text', 'shape', 'pic'});
      await tester.pump();
      // The row holds every group now, so arrange scrolls into view.
      await tester.ensureVisible(key('slide_distribute'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_distribute'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_distribute_vertical'));
      await tester.pumpAndSettle();

      // Distribute, ungroup, group, match size, align left, align top.
      for (var i = 0; i < 6; i++) {
        c.undo();
      }
      await tester.pump();
      expect(c.canUndo, isFalse);
      expect(element(c, 'shape').frame.y, 500);
      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);
      await letAutosaveRun(tester);
    });

    testWidgets('the toolbar copies, cuts and pastes through the clipboard, '
        'and pastes plain text as a text box', (tester) async {
      tap.setViewport(tester, tap.wideViewport);
      final c = await pumpDrawn(tester);
      // Paste is offered with nothing selected; copy and cut are not.
      expect(key(SlideToolbarGroup.clipboard.key), findsOneWidget);
      expect(key('slide_format_hint'), findsOneWidget);

      c.selectElements({'shape'});
      await tester.pump();
      await tester.tap(key('slide_copy'));
      await tester.pumpAndSettle();
      expect(clipboardText, isNotNull);
      await tester.tap(key('slide_paste'));
      await tester.pumpAndSettle();
      expect(c.selectedSlide!.elements, hasLength(4));
      final pasted = c.singleSelected!;
      expect(pasted.id, isNot('shape'));
      expect(pasted.frame.x, 200 + SlideDocumentController.pasteOffset);

      await tester.tap(key('slide_cut'));
      await tester.pumpAndSettle();
      expect(c.selectedSlide!.elements, hasLength(3));
      expect(c.selectedElementIds, isEmpty);

      clipboardText = 'From another app';
      await tester.tap(key('slide_paste'));
      await tester.pumpAndSettle();
      final box = c.singleSelected;
      expect(box, isA<TextBox>());
      expect((box! as TextBox).plainText, 'From another app');

      c
        ..undo()
        ..undo()
        ..undo();
      await tester.pump();
      expect(c.canUndo, isFalse);
      await letAutosaveRun(tester);
    });

    testWidgets('the canvas copy and paste keys use the same clipboard', (
      tester,
    ) async {
      tap.setViewport(tester, tap.wideViewport);
      final c = await pumpDrawn(tester);
      c.selectElements({'shape'});
      await tester.pump();
      // The canvas has focus from the start.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(clipboardText, isNotNull);
      expect(c.canUndo, isFalse);
      await letAutosaveRun(tester);
    });

    for (final (name, size) in [
      ('narrow', tap.narrowViewport),
      ('wide', tap.wideViewport),
    ]) {
      testWidgets('the properties set the slide background color ($name)', (
        tester,
      ) async {
        tap.setViewport(tester, size);
        final c = await pumpDrawn(tester);
        if (size == tap.narrowViewport) {
          await tester.tap(key('slide_format_menu'));
          await tester.pumpAndSettle();
          await tester.tap(key('slide_format_properties'));
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(key('slide_background_hex'));
        await tester.enterText(key('slide_background_hex'), '#102030');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(
          c.selectedSlide!.background?.color,
          const SlideColor(0xFF102030),
        );
        expect(c.saveState, SlideSaveState.dirty);

        await tester.ensureVisible(key('slide_background_none'));
        await tester.tap(key('slide_background_none'));
        await tester.pumpAndSettle();
        expect(c.selectedSlide!.background, isNull);
        c
          ..undo()
          ..undo();
        expect(c.canUndo, isFalse);
        expect(tester.takeException(), isNull);
        await letAutosaveRun(tester);
      });
    }

    testWidgets('a phone arranges and pastes from the Format menu', (
      tester,
    ) async {
      tap.setViewport(tester, tap.narrowViewport);
      final c = await pumpDrawn(tester);
      c.selectElements({'shape', 'pic'});
      await tester.pump();
      await tester.tap(key('slide_format_menu'));
      await tester.pumpAndSettle();
      await tester.tap(key(SlideToolbarGroup.arrange.key));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_group'));
      await tester.pumpAndSettle();
      expect(c.singleSelected, isA<GroupElement>());

      await tester.tap(key('slide_format_menu'));
      await tester.pumpAndSettle();
      await tester.tap(key(SlideToolbarGroup.clipboard.key));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_copy'));
      await tester.pumpAndSettle();
      expect(clipboardText, isNotNull);
      expect(tester.takeException(), isNull);
      await letAutosaveRun(tester);
    });
  });

  group('keyboard shortcuts help (#1168)', () {
    Finder dialog() => find.byKey(const ValueKey('slide_shortcuts_dialog'));

    testWidgets('? opens the shortcuts dialog from the canvas', (tester) async {
      tap.setViewport(tester, tap.wideViewport);
      await pumpEditor(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(dialog(), findsOneWidget);
    });

    testWidgets('F1 opens it too', (tester) async {
      tap.setViewport(tester, tap.wideViewport);
      await pumpEditor(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(dialog(), findsOneWidget);
    });

    testWidgets('the toolbar\'s keyboard button opens it (wide)', (
      tester,
    ) async {
      tap.setViewport(tester, tap.wideViewport);
      await pumpEditor(tester);
      final button = find.byKey(const ValueKey('slide_shortcuts_button'));
      expect(find.byTooltip('Keyboard shortcuts'), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(dialog(), findsOneWidget);
      await tap.expectTapTargetGuidelines(tester);
    });

    testWidgets('a phone opens it from the Format menu (narrow)', (
      tester,
    ) async {
      tap.setViewport(tester, tap.narrowViewport);
      await pumpEditor(tester);
      await tester.tap(find.byKey(const ValueKey('slide_format_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slide_format_shortcuts')));
      await tester.pumpAndSettle();
      expect(dialog(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('transitions (#1164)', () {
    Finder key(String k) => find.byKey(ValueKey(k));

    testWidgets('a wide window picks a kind, direction and length from the '
        'panel, marks the slide and undoes each step', (tester) async {
      tap.setViewport(tester, tap.wideViewport);
      final c = await pumpEditor(tester);
      expect(key('slide_transition_kind_none'), findsOneWidget);
      expect(key('slide_transition_direction_left'), findsNothing);
      expect(key('slide_transition_duration'), findsNothing);
      expect(key('slide_transition_marker'), findsNothing);

      await tester.ensureVisible(key('slide_transition_kind_push'));
      await tester.tap(key('slide_transition_kind_push'));
      await tester.pumpAndSettle();
      expect(c.slideTransition?.kind, SlideTransitionKind.push);
      expect(c.saveState, SlideSaveState.dirty);
      expect(key('slide_transition_marker'), findsOneWidget);

      await tester.ensureVisible(key('slide_transition_direction_up'));
      await tester.tap(key('slide_transition_direction_up'));
      await tester.pumpAndSettle();
      expect(c.slideTransition?.direction, SlideTransitionDirection.up);

      await tester.ensureVisible(key('slide_transition_duration'));
      await tester.drag(key('slide_transition_duration'), const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(c.slideTransition?.durationMs, SlideTransitionSpec.maxDurationMs);
      expect(find.text('2000 ms'), findsOneWidget);

      // Length, direction and kind were one undo step each.
      c.undo();
      expect(
        c.slideTransition?.durationMs,
        SlideTransitionSpec.defaultDurationMs,
      );
      c.undo();
      expect(c.slideTransition?.direction, SlideTransitionDirection.left);
      c.undo();
      await tester.pumpAndSettle();
      expect(c.slideTransition, isNull);
      expect(c.canUndo, isFalse);
      expect(key('slide_transition_marker'), findsNothing);

      await tester.ensureVisible(key('slide_transition_kind_wipe'));
      await tester.tap(key('slide_transition_kind_wipe'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(key('slide_transition_apply_all'));
      await tester.tap(key('slide_transition_apply_all'));
      await tester.pumpAndSettle();
      expect(c.presentation!.defaultTransition.kind, SlideTransitionKind.wipe);
      expect(c.slides.every((s) => s.transition == null), isTrue);
      expect(tester.takeException(), isNull);
      await letAutosaveRun(tester);
    });

    testWidgets('Preview plays the transition once in the panel', (
      tester,
    ) async {
      tap.setViewport(tester, tap.wideViewport);
      final c = await pumpEditor(tester);
      c.setSlideTransition(const SlideTransitionSpec.fade());
      await tester.pumpAndSettle();
      await tester.ensureVisible(key('slide_transition_preview'));
      await tester.tap(key('slide_transition_preview'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SlideTransitionView), findsOneWidget);
      // Both slides are on the stage mid-way.
      expect(
        find.descendant(
          of: key('slide_transition_stage'),
          matching: find.byType(SlideCanvas),
        ),
        findsNWidgets(2),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: key('slide_transition_stage'),
          matching: find.byType(SlideCanvas),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await letAutosaveRun(tester);
    });

    testWidgets('the Transition chip opens the picker beside the panel\'s', (
      tester,
    ) async {
      tap.setViewport(tester, tap.wideViewport);
      final c = await pumpEditor(tester);
      await tester.tap(key('slide_transition_button'));
      await tester.pumpAndSettle();
      expect(key('slide_transition_kind_zoom'), findsNWidgets(2));
      await tester.tap(key('slide_transition_kind_zoom').first);
      await tester.pumpAndSettle();
      expect(c.slideTransition?.kind, SlideTransitionKind.zoom);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await letAutosaveRun(tester);
    });

    testWidgets('a phone opens the picker from Format in a sheet', (
      tester,
    ) async {
      tap.setViewport(tester, tap.narrowViewport);
      final c = await pumpEditor(tester);
      await tester.tap(key('slide_format_menu'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_format_transition'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_transition_kind_fade'));
      await tester.pumpAndSettle();
      expect(c.slideTransition?.kind, SlideTransitionKind.fade);
      expect(key('slide_transition_duration'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(180, 20));
      await tester.pumpAndSettle();
      await letAutosaveRun(tester);
    });

    testWidgets('a view-only deck shows the transition with its choices off', (
      tester,
    ) async {
      tap.setViewport(tester, tap.wideViewport);
      final c = await pumpEditor(tester, readOnly: true);
      expect(key('slide_transition_kind_none'), findsOneWidget);
      await tester.ensureVisible(key('slide_transition_kind_fade'));
      await tester.tap(key('slide_transition_kind_fade'));
      await tester.pumpAndSettle();
      expect(c.slideTransition, isNull);
      expect(key('slide_transition_apply_all'), findsNothing);
    });

    testLargeText('the picker fits', (tester, size) async {
      final c = await pumpEditor(tester);
      c.setSlideTransition(
        const SlideTransitionSpec(kind: SlideTransitionKind.wipe),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await letAutosaveRun(tester);
    });
  });

  group('themes and layouts (#1163)', () {
    Finder key(String k) => find.byKey(ValueKey(k));

    testWidgets('a deck with no theme says so, and a wide window applies '
        'one from the panel and another from the toolbar', (tester) async {
      tap.setViewport(tester, tap.wideViewport);
      final c = await pumpEditor(tester);
      expect(key('slide_theme_none'), findsOneWidget);

      await tester.ensureVisible(key('slide_theme_apply'));
      await tester.tap(key('slide_theme_apply'));
      await tester.pumpAndSettle();
      expect(c.theme, SlideThemes.all.first);
      expect(key('slide_theme_none'), findsNothing);

      await tester.tap(key('slide_theme_button'));
      await tester.pumpAndSettle();
      // The panel's picker and the menu's.
      expect(key('slide_theme_dark'), findsNWidgets(2));
      await tester.tap(key('slide_theme_dark').last);
      await tester.pumpAndSettle();
      expect(c.theme, SlideThemes.dark);
      expect(c.saveState, SlideSaveState.dirty);
      final drawn = tester.widget<SlideCanvas>(
        find.descendant(of: thumb('s1'), matching: find.byType(SlideCanvas)),
      );
      expect(drawn.theme, SlideThemes.dark);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.tap(key('slide_editor_undo'));
      await tester.pumpAndSettle();
      expect(c.theme, SlideThemes.all.first);
      expect(tester.takeException(), isNull);
      await letAutosaveRun(tester);
    });

    testWidgets('a wide window changes and resets the slide\'s layout, and '
        'adds slides on a layout', (tester) async {
      tap.setViewport(tester, tap.wideViewport);
      final c = await pumpEditor(tester);
      // Only the menu's picker, not the properties panel's.
      await tester.tap(key('slide_properties_toggle'));
      await tester.pumpAndSettle();

      await tester.tap(key('slide_layout_button'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_layout_titleAndContent'));
      await tester.pumpAndSettle();
      expect(c.selectedLayoutId, SlideLayout.titleAndContent.id);
      // The typed text is kept as an ordinary box beside the placeholders.
      expect(c.selectedSlide!.findElement('t1'), isNotNull);
      await tester.tap(key('slide_layout_reset'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // A plain tap copies the layout; the chevron picks one.
      await tester.tap(key('slide_panel_add'));
      await tester.pumpAndSettle();
      expect(c.selectedLayoutId, SlideLayout.titleAndContent.id);
      await tester.tap(key('slide_panel_add_menu'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_panel_add_sectionHeader'));
      await tester.pumpAndSettle();
      expect(c.selectedLayoutId, SlideLayout.sectionHeader.id);
      expect(c.slides, hasLength(4));
      expect(tester.takeException(), isNull);
      await letAutosaveRun(tester);
    });

    testWidgets('a phone picks the theme and layout in sheets from Format, '
        'and a new slide\'s layout from Insert', (tester) async {
      tap.setViewport(tester, tap.narrowViewport);
      final c = await pumpEditor(tester);

      await tester.tap(key('slide_format_menu'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_format_theme'));
      await tester.pumpAndSettle();
      expect(find.text('No theme'), findsOneWidget);
      await tester.tap(key('slide_theme_warm'));
      await tester.pumpAndSettle();
      expect(c.theme, SlideThemes.warm);
      // The sheet follows the pick.
      expect(find.text('No theme'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(180, 20));
      await tester.pumpAndSettle();

      await tester.tap(key('slide_format_menu'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_format_layout'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(key('slide_layout_twoContent'));
      await tester.tap(key('slide_layout_twoContent'));
      await tester.pumpAndSettle();
      expect(c.selectedLayoutId, SlideLayout.twoContent.id);
      await tester.tapAt(const Offset(180, 20));
      await tester.pumpAndSettle();

      await tester.tap(key('slide_insert_menu'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_insert_slide'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_new_slide_title'));
      await tester.pumpAndSettle();
      expect(c.selectedLayoutId, SlideLayout.title.id);
      expect(c.selectedIndex, 1);
      expect(tester.takeException(), isNull);
      await letAutosaveRun(tester);
    });

    testLargeText('the pickers fit', (tester, size) async {
      final c = await pumpEditor(tester);
      c.applyTheme(SlideThemes.cool);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await letAutosaveRun(tester);
    });
  });

  group('find and replace (#1176)', () {
    Finder key(String name) => find.byKey(ValueKey(name));

    Future<void> chord(WidgetTester tester, LogicalKeyboardKey k) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(k);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    String status(WidgetTester tester) =>
        tester.widget<Text>(key('slide_find_status')).data!;

    String textOf(SlideEditorController c, int slide) =>
        (c.slides[slide - 1].elements.single as TextBox).paragraphs.single.runs
            .map((r) => r.text)
            .join();

    Future<void> search(WidgetTester tester, String query) async {
      await chord(tester, LogicalKeyboardKey.keyF);
      await tester.enterText(key('slide_find_query'), query);
      await tester.pump();
    }

    for (final (name, size) in [
      ('narrow', tap.narrowViewport),
      ('wide', tap.wideViewport),
    ]) {
      testWidgets('Ctrl F opens the bar, the counter and Next wrap, Escape '
          'closes and clears the highlights ($name)', (tester) async {
        tap.setViewport(tester, size);
        await pumpEditor(tester);
        expect(key('slide_find_bar'), findsNothing);
        SlideCanvas canvas() => tester.widget<SlideCanvas>(
          find.byKey(const ValueKey('slide_editor_canvas')),
        );

        await search(tester, 'text');
        expect(key('slide_find_bar'), findsOneWidget);
        expect(status(tester), '1 of 2');
        expect(canvas().highlights, hasLength(2));
        expect(canvas().currentHighlight?.slideId, 's1');

        await tester.tap(key('slide_find_next'));
        await tester.pump();
        expect(status(tester), '2 of 2');
        expect(canvas().currentHighlight?.slideId, 's2');

        await tester.tap(key('slide_find_next'));
        await tester.pump();
        expect(status(tester), '1 of 2');
        expect(canvas().currentHighlight?.slideId, 's1');

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(key('slide_find_bar'), findsNothing);
        expect(canvas().highlights, isEmpty);
        expect(canvas().currentHighlight, isNull);
      });

      testWidgets('replacing one match is one undo step ($name)', (
        tester,
      ) async {
        tap.setViewport(tester, size);
        final c = await pumpEditor(tester);
        await chord(tester, LogicalKeyboardKey.keyH);
        await tester.enterText(key('slide_find_query'), 'text');
        await tester.enterText(key('slide_find_replacement'), 'word');
        await tester.pump();

        await tester.tap(key('slide_find_replace'));
        await tester.pump();
        expect(textOf(c, 1), 'Slide word 1');
        expect(textOf(c, 2), 'Slide text 2');
        expect(status(tester), '1 of 1');

        await tester.tap(key('slide_editor_undo'));
        await tester.pump();
        expect(textOf(c, 1), 'Slide text 1');
        expect(textOf(c, 2), 'Slide text 2');
        expect(c.canUndo, isFalse);
        await letAutosaveRun(tester);
      });

      testWidgets('Replace all changes every match in one undo ($name)', (
        tester,
      ) async {
        tap.setViewport(tester, size);
        final c = await pumpEditor(tester);
        await chord(tester, LogicalKeyboardKey.keyH);
        await tester.enterText(key('slide_find_query'), 'text');
        await tester.enterText(key('slide_find_replacement'), 'word');
        await tester.pump();

        await tester.tap(key('slide_find_replace_all'));
        await tester.pump();
        expect(textOf(c, 1), 'Slide word 1');
        expect(textOf(c, 2), 'Slide word 2');
        expect(status(tester), 'No results');

        await tester.tap(key('slide_editor_undo'));
        await tester.pump();
        expect(textOf(c, 1), 'Slide text 1');
        expect(textOf(c, 2), 'Slide text 2');
        expect(c.canUndo, isFalse);
        await letAutosaveRun(tester);
      });
    }

    testWidgets('the wide tool row button opens and closes the bar', (
      tester,
    ) async {
      tap.setViewport(tester, tap.wideViewport);
      await pumpEditor(tester);
      await tester.tap(key('slide_find_open'));
      await tester.pumpAndSettle();
      expect(key('slide_find_bar'), findsOneWidget);
      await tester.tap(key('slide_find_open'));
      await tester.pumpAndSettle();
      expect(key('slide_find_bar'), findsNothing);
    });

    testWidgets("the phone Format menu's Find and replace opens the bar", (
      tester,
    ) async {
      tap.setViewport(tester, tap.narrowViewport);
      await pumpEditor(tester);
      expect(key('slide_find_open'), findsNothing);
      await tester.tap(key('slide_format_menu'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_format_find'));
      await tester.pumpAndSettle();
      expect(key('slide_find_bar'), findsOneWidget);
    });

    testLargeText('the bar fits', (tester, size) async {
      await pumpEditor(tester);
      await search(tester, 'text');
      expect(status(tester), '1 of 2');
      expect(tester.takeException(), isNull);
    });
  });
  group('sharing and view only (#1170)', () {
    Finder key(String k) => find.byKey(ValueKey(k));

    testWidgets('the wide bar has Share, and it opens the share sheet', (
      tester,
    ) async {
      resetSharedHttpClient();
      sharedHttpClientFactory = () =>
          MockClient((_) async => http.Response('{}', 500));
      addTearDown(resetSharedHttpClient);
      tap.setViewport(tester, tap.wideViewport);
      await pumpEditor(tester);
      expect(find.byTooltip('Share'), findsOneWidget);
      await tester.tap(key('slide_editor_share'));
      await tester.pumpAndSettle();
      expect(find.text('Share Deck'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the phone bar leaves Share to the Format menu', (
      tester,
    ) async {
      tap.setViewport(tester, tap.narrowViewport);
      await pumpEditor(tester);
      expect(key('slide_editor_share'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final (name, size) in [
      ('narrow', tap.narrowViewport),
      ('wide', tap.wideViewport),
    ]) {
      testWidgets('a deck that can be edited has no View only ($name)', (
        tester,
      ) async {
        tap.setViewport(tester, size);
        await pumpEditor(tester);
        expect(key('slide_editor_view_only'), findsNothing);
        expect(key('slide_editor_save'), findsOneWidget);
      });

      testWidgets(
        'read-only says View only, in place of the save chip ($name)',
        (tester) async {
          tap.setViewport(tester, size);
          await pumpEditor(tester, readOnly: true);
          expect(key('slide_editor_view_only'), findsOneWidget);
          // A phone's bar has only the lock; its words follow the position.
          expect(
            find.text(
              size == tap.wideViewport
                  ? 'View only'
                  : 'Slide 1 of 2 · View only',
            ),
            findsOneWidget,
          );
          expect(find.byTooltip(SlideViewOnlyBadge.tooltip), findsOneWidget);
          expect(
            find.bySemanticsLabel(RegExp('^View only\\.')),
            findsOneWidget,
          );
          expect(key('slide_editor_save'), findsNothing);
          expect(tester.takeException(), isNull);
          await tap.expectTapTargetGuidelines(tester);
        },
      );

      testWidgets('read-only keeps Present, Export, Share and zoom ($name)', (
        tester,
      ) async {
        tap.setViewport(tester, size);
        final c = await pumpEditor(tester, readOnly: true);
        QuarkBarChip present() => tester.widget(key('slide_editor_present'));
        expect(present().onPressed, isNotNull);
        expect(
          tester
              .widget<SlideExportButton>(key('slide_editor_export_pptx'))
              .onPressed,
          isNotNull,
        );
        if (size == tap.wideViewport) {
          expect(
            tester
                .widget<SlideShareButton>(key('slide_editor_share'))
                .onPressed,
            isNotNull,
          );
          await tester.tap(key('slide_zoom_in'));
        } else {
          // A phone's bar keeps Share and zoom in the Format menu.
          await tester.tap(key('slide_format_menu'));
          await tester.pumpAndSettle();
          expect(key('slide_format_share'), findsOneWidget);
          await tester.tap(key('slide_zoom_menu'));
          await tester.pumpAndSettle();
          await tester.tap(key('slide_menu_zoom_in'));
        }
        await tester.pumpAndSettle();
        expect(c.zoom, greaterThan(1));
        await tester.tap(thumb('s2'));
        await tester.pumpAndSettle();
        expect(c.selectedSlideId, 's2');
      });

      testWidgets(
        'read-only turns undo, redo and the panel edits off ($name)',
        (tester) async {
          tap.setViewport(tester, size);
          final c = await pumpEditor(tester, readOnly: true);
          expect(
            tester
                .widget<QuarkBarIconButton>(key('slide_editor_undo'))
                .onPressed,
            isNull,
          );
          expect(
            tester
                .widget<QuarkBarIconButton>(key('slide_editor_redo'))
                .onPressed,
            isNull,
          );
          expect(
            tester.widget<QuarkBarIconButton>(key('slide_panel_add')).onPressed,
            isNull,
          );
          await tester.tap(key('slide_menu_s1'));
          await tester.pumpAndSettle();
          for (final row in ['duplicate', 'move_later', 'delete']) {
            expect(
              tester.widget<PopupMenuItem<int>>(key('slide_${row}_s1')).enabled,
              isFalse,
              reason: row,
            );
          }
          expect(key('slide_present_s1'), findsOneWidget);
          await tester.tapAt(const Offset(1, 1));
          await tester.pumpAndSettle();
          expect(c.slides.length, 2);
        },
      );

      testWidgets('read-only notes can be read but not typed in ($name)', (
        tester,
      ) async {
        tap.setViewport(tester, size);
        final c = await pumpEditor(tester, readOnly: true);
        c.toggleNotes();
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(key('slide_notes_field')).readOnly,
          isTrue,
        );
        c.editNotes('typed');
        expect(c.isDirty, isFalse);
        expect(c.notes, isEmpty);
      });

      testWidgets('read-only canvas ignores edits and keys ($name)', (
        tester,
      ) async {
        tap.setViewport(tester, size);
        final c = await pumpEditor(tester, readOnly: true);
        final before = c.presentation;
        c.selectElements({'t1'});
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.drag(key('slide_editor_canvas'), const Offset(80, 40));
        await tester.pumpAndSettle();
        expect(c.presentation, same(before));
        c
          ..deleteSelection()
          ..addSlide()
          ..applyTheme(null)
          ..setFrame(x: 5);
        await tester.pumpAndSettle();
        expect(c.presentation, same(before));
        expect(c.isDirty, isFalse);
        await tester.pump(const Duration(seconds: 3));
        expect(saved, isEmpty);
      });

      testWidgets('read-only find searches without replace ($name)', (
        tester,
      ) async {
        tap.setViewport(tester, size);
        await pumpEditor(tester, readOnly: true);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(key('slide_find_bar'), findsOneWidget);
        await tester.enterText(key('slide_find_query'), 'text');
        await tester.pumpAndSettle();
        expect(find.text('1 of 2'), findsOneWidget);
        expect(key('slide_find_toggle_replace'), findsNothing);
        expect(key('slide_find_replace_all'), findsNothing);
        expect(key('slide_find_next'), findsOneWidget);
      });
    }

    testWidgets('wide read-only toolbar drops the tools, keeps find', (
      tester,
    ) async {
      tap.setViewport(tester, tap.wideViewport);
      await pumpEditor(tester, readOnly: true);
      for (final gone in [
        'slide_tool_shape',
        'slide_tool_image',
        'slide_theme_button',
        'slide_layout_button',
        'slide_transition_button',
        'slide_format_hint',
      ]) {
        expect(key(gone), findsNothing, reason: gone);
      }
      expect(key('slide_find_open'), findsOneWidget);
      expect(key('slide_shortcuts_button'), findsOneWidget);
    });

    testWidgets('wide read-only properties show values, take no input', (
      tester,
    ) async {
      tap.setViewport(tester, tap.wideViewport);
      final c = await pumpEditor(tester, readOnly: true);
      c.selectElements({'t1'});
      await tester.pumpAndSettle();
      expect(key('slide_properties'), findsOneWidget);
      for (final field in ['x', 'y', 'width', 'height', 'rotation']) {
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: key('slide_prop_$field'),
                  matching: find.byType(TextField),
                ),
              )
              .readOnly,
          isTrue,
          reason: field,
        );
      }
      expect(key('slide_background'), findsNothing);
      expect(key('slide_theme_picker'), findsNothing);
    });

    testWidgets('phone read-only menus: no Insert, Format has Share and Find', (
      tester,
    ) async {
      tap.setViewport(tester, tap.narrowViewport);
      await pumpEditor(tester, readOnly: true);
      expect(key('slide_insert_menu'), findsNothing);
      await tester.tap(key('slide_format_menu'));
      await tester.pumpAndSettle();
      expect(key('slide_format_find'), findsOneWidget);
      expect(key('slide_format_share'), findsOneWidget);
      expect(key('slide_format_properties'), findsOneWidget);
      expect(key('slide_zoom_menu'), findsOneWidget);
      expect(key('slide_format_theme'), findsNothing);
      expect(key('slide_format_layout'), findsNothing);
      expect(key('slide_format_transition'), findsNothing);
      for (final group in SlideToolbarGroup.values) {
        expect(key(group.key), findsNothing, reason: group.key);
      }
    });

    testWidgets('phone Format menu shares too', (tester) async {
      resetSharedHttpClient();
      sharedHttpClientFactory = () =>
          MockClient((_) async => http.Response('{}', 500));
      addTearDown(resetSharedHttpClient);
      tap.setViewport(tester, tap.narrowViewport);
      await pumpEditor(tester);
      await tester.tap(key('slide_format_menu'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_format_share'));
      await tester.pumpAndSettle();
      expect(find.text('Share Deck'), findsOneWidget);
    });

    for (final (name, size) in [
      ('narrow', tap.narrowViewport),
      ('wide', tap.wideViewport),
    ]) {
      testWidgets(
        'a 403 on save flips to View only without a snack bar ($name)',
        (tester) async {
          tap.setViewport(tester, size);
          saveFailure = const ApiException(403, 'save');
          final c = await pumpEditor(tester);
          expect(key('slide_editor_view_only'), findsNothing);
          c.addSlide();
          await tester.pump();
          await letAutosaveRun(tester);
          expect(c.isReadOnly, isTrue);
          expect(key('slide_editor_view_only'), findsOneWidget);
          expect(key('slide_editor_save'), findsNothing);
          expect(find.byType(SnackBar), findsNothing);
          expect(find.textContaining(Errors.couldNot('save')), findsNothing);
          expect(saved, isEmpty);
          // Nothing keeps retrying.
          await tester.pump(const Duration(seconds: 5));
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
