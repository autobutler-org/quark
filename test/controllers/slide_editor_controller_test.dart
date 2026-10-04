import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/services/slides_service.dart';
import 'package:quark_slides/quark_slides.dart';

/// The slide editor's state: loading the `.qslide`, the slide panel's
/// commands and selection, undo and redo, and the debounced autosave (#1161).
void main() {
  Presentation deck(int count) => Presentation(
    title: 'Deck',
    slides: [for (var i = 1; i <= count; i++) Slide(id: 's$i')],
  );

  late List<Presentation> saved;
  late Object? saveFailure;

  SlideEditorController controllerFor(
    Presentation presentation, {
    Completer<void>? saveGate,
    bool disposeAtEnd = true,
  }) {
    var next = 0;
    final controller = SlideEditorController(
      filePath: 'talks/deck.qslide',
      deviceSerial: 'usb1',
      loadPresentation: (path, {serial}) async {
        expect(path, 'talks/deck.qslide');
        expect(serial, 'usb1');
        return presentation;
      },
      savePresentation: (path, p, {serial}) async {
        if (saveGate != null) await saveGate.future;
        final failure = saveFailure;
        if (failure != null) throw failure;
        saved.add(p);
      },
      newId: () => 'n${next++}',
    );
    // No autosave timer outlives its test.
    if (disposeAtEnd) addTearDown(controller.dispose);
    return controller;
  }

  setUp(() {
    saved = [];
    saveFailure = null;
  });

  List<String> ids(SlideEditorController c) => [for (final s in c.slides) s.id];

  test('loads the presentation and selects its first slide', () async {
    final c = controllerFor(deck(2));
    expect(c.isLoading, isTrue);
    await c.load();
    expect(c.isLoading, isFalse);
    expect(c.loadError, isNull);
    expect(ids(c), ['s1', 's2']);
    expect(c.selectedSlideId, 's1');
    expect(c.saveState, SlideSaveState.saved);
    expect(c.canUndo, isFalse);
  });

  test('a failed load is kept as the thrown object', () async {
    final failure = Exception('boom');
    final c = SlideEditorController(
      filePath: 'x.qslide',
      loadPresentation: (_, {serial}) async => throw failure,
    );
    await c.load();
    expect(c.isLoading, isFalse);
    expect(c.loadError, same(failure));
    expect(c.presentation, isNull);
  });

  test('add puts a slide after the selected one and selects it', () async {
    final c = controllerFor(deck(2));
    await c.load();
    c.addSlide();
    expect(ids(c), ['s1', 'n0', 's2']);
    expect(c.selectedSlideId, 'n0');
    expect(c.saveState, SlideSaveState.dirty);
  });

  test('duplicate copies in after the slide and selects the copy', () async {
    final c = controllerFor(deck(2));
    await c.load();
    c.duplicateSlide('s2');
    expect(ids(c), ['s1', 's2', 'n0']);
    expect(c.selectedSlideId, 'n0');
  });

  test('delete moves the selection and never removes the last slide', () async {
    final c = controllerFor(deck(3));
    await c.load();
    c.selectSlide('s3');
    c.deleteSlide('s3');
    expect(ids(c), ['s1', 's2']);
    expect(c.selectedSlideId, 's2');
    c.selectSlide('s1');
    c.deleteSlide('s1');
    expect(ids(c), ['s2']);
    expect(c.selectedSlideId, 's2');
    expect(c.canDeleteSlide, isFalse);
    c.deleteSlide('s2');
    expect(ids(c), ['s2']);
  });

  test('move reorders and keeps the selection on the moved slide', () async {
    final c = controllerFor(deck(3));
    await c.load();
    c.moveSlide('s1', 2);
    expect(ids(c), ['s2', 's3', 's1']);
    expect(c.selectedSlideId, 's1');
    expect(c.selectedIndex, 2);
  });

  test('undo and redo walk the history and keep a valid selection', () async {
    final c = controllerFor(deck(1));
    await c.load();
    c.addSlide();
    expect(c.selectedSlideId, 'n0');
    c.undo();
    expect(ids(c), ['s1']);
    expect(c.selectedSlideId, 's1');
    expect(c.canRedo, isTrue);
    // Back where the file was: nothing to save.
    expect(c.saveState, SlideSaveState.saved);
    c.redo();
    expect(ids(c), ['s1', 'n0']);
    expect(c.saveState, SlideSaveState.dirty);
  });

  // testWidgets for its fake clock: the autosave is a timer.
  testWidgets('autosave waits for a two second pause in editing', (
    tester,
  ) async {
    final c = controllerFor(deck(1));
    await c.load();
    c.addSlide();
    await tester.pump(const Duration(milliseconds: 1500));
    c.addSlide();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(saved, isEmpty, reason: 'the second edit restarts the pause');
    await tester.pump(const Duration(milliseconds: 600));
    expect(saved, hasLength(1));
    expect(saved.single.slides, hasLength(3));
    expect(c.saveState, SlideSaveState.saved);
  });

  testWidgets('an edit during a save is saved after it lands', (tester) async {
    final gate = Completer<void>();
    final c = controllerFor(deck(1), saveGate: gate);
    await c.load();
    c.addSlide();
    await tester.pump(const Duration(seconds: 2));
    expect(c.saveState, SlideSaveState.saving);
    c.addSlide();
    gate.complete();
    await tester.pump();
    expect(saved, hasLength(1));
    expect(c.saveState, SlideSaveState.dirty);
    await tester.pump(const Duration(seconds: 2));
    expect(saved, hasLength(2));
    expect(saved.last.slides, hasLength(3));
    expect(c.saveState, SlideSaveState.saved);
  });

  test('a failed save is reported and kept dirty until a retry', () async {
    final c = controllerFor(deck(1));
    final reported = <Object>[];
    c.onSaveFailed = reported.add;
    await c.load();
    c.addSlide();
    saveFailure = Exception('offline');
    expect(await c.save(), isFalse);
    expect(c.saveState, SlideSaveState.failed);
    expect(c.saveError, same(saveFailure));
    expect(reported, [saveFailure]);

    saveFailure = null;
    expect(await c.save(), isTrue);
    expect(c.saveState, SlideSaveState.saved);
    expect(c.saveError, isNull);
  });

  testWidgets('leaving inside the pause saves the pending edits', (
    tester,
  ) async {
    final c = controllerFor(deck(1), disposeAtEnd: false);
    await c.load();
    c.addSlide();
    c.dispose();
    await tester.pump();
    expect(saved, hasLength(1));
    await tester.pump(const Duration(seconds: 5));
    expect(saved, hasLength(1));
  });

  test('a new presentation is one centered title slide at 16:9', () {
    final p = SlidesService.newPresentation('Pitch');
    expect(p.title, 'Pitch');
    expect(p.size, SlideSize.widescreen);
    expect(p.slides, hasLength(1));
    final title = p.slides.single.elements.single as TextBox;
    expect(title.plainText, 'Pitch');
    expect(title.paragraphs.single.alignment, TextAlignment.center);
    // It survives the file format.
    expect(QslideCodec.decode(QslideCodec.encode(p)), p);
  });

  Presentation withElements() => Presentation(
    title: 'Deck',
    slides: [
      Slide(
        id: 's1',
        elements: [
          ShapeElement(
            id: 'a',
            kind: ShapeKind.rectangle,
            frame: ElementFrame(x: 0, y: 0, width: 100, height: 100),
          ),
          ShapeElement(
            id: 'b',
            kind: ShapeKind.rectangle,
            frame: ElementFrame(x: 200, y: 0, width: 100, height: 100),
          ),
        ],
      ),
      Slide(id: 's2'),
    ],
  );

  test('the canvas selection lives here and follows the slide', () async {
    final c = controllerFor(withElements());
    await c.load();
    expect(c.selectedElementIds, isEmpty);
    c.selectElements({'a', 'b'});
    expect(c.selectedElementIds, {'a', 'b'});

    // An element deleted on the canvas leaves the selection.
    c.document!.controller.deleteElements('s1', {'a'});
    expect(c.selectedElementIds, {'b'});

    // Another slide starts with nothing selected.
    c.selectSlide('s2');
    expect(c.selectedElementIds, isEmpty);
    c.selectSlide('s1');
    c.selectElements({'b'});
    c.addSlide();
    expect(c.selectedElementIds, isEmpty);
    await c.save();
  });

  test('a canvas edit is dirty, undoable and autosaved', () async {
    final c = controllerFor(withElements());
    await c.load();
    c.document!.controller.moveElements('s1', {'a'}, 10, 0);
    expect(c.isDirty, isTrue);
    expect(c.canUndo, isTrue);
    expect(c.saveState, SlideSaveState.dirty);
    await c.save();
    expect(saved.single.slides.first.elements.first.frame.x, 10);
    c.undo();
    expect(c.isDirty, isTrue);
    expect(c.presentation!.slides.first.elements.first.frame.x, 0);
    await c.save();
  });

  test('zoom steps between fixed levels within the canvas range', () async {
    final c = controllerFor(deck(1));
    await c.load();
    expect(c.zoom, 1);
    expect(c.zoomPercent, '100%');
    c.zoomIn();
    expect(c.zoom, 1.25);
    c.zoomIn();
    c.zoomIn();
    c.zoomIn();
    expect(c.zoom, SlideCanvas.maxZoom);
    expect(c.canZoomIn, isFalse);
    c.zoomIn();
    expect(c.zoom, SlideCanvas.maxZoom);
    c.zoomToFit();
    expect(c.zoom, 1);
    // A pinch lands between levels; the buttons step to the next one.
    c.setZoom(0.8);
    expect(c.zoomPercent, '80%');
    c.zoomOut();
    expect(c.zoom, 0.75);
    c.zoomOut();
    expect(c.zoom, SlideCanvas.minZoom);
    expect(c.canZoomOut, isFalse);
    c.setZoom(9);
    expect(c.zoom, SlideCanvas.maxZoom);
  });

  test(
    'previous and next step through the slides and stop at the ends',
    () async {
      final c = controllerFor(deck(3));
      await c.load();
      c.selectPreviousSlide();
      expect(c.selectedSlideId, 's1');
      c.selectNextSlide();
      c.selectNextSlide();
      expect(c.selectedSlideId, 's3');
      c.selectNextSlide();
      expect(c.selectedSlideId, 's3');
      c.selectPreviousSlide();
      expect(c.selectedSlideId, 's2');
    },
  );

  test('an image source is fetched from the presentation\'s device', () {
    final calls = <(String, String?)>[];
    final c = SlideEditorController(
      filePath: 'talks/deck.qslide',
      deviceSerial: 'usb1',
      mediaUrl: (path, {serial}) {
        calls.add((path, serial));
        return Uri.parse('https://quark.test/$path');
      },
    );
    addTearDown(c.dispose);
    expect(
      c.imageUrl('/photos/a.png'),
      Uri.parse('https://quark.test/photos/a.png'),
    );
    expect(calls.single, ('photos/a.png', 'usb1'));
  });
}
