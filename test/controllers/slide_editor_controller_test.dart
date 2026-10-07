import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/services/slides_service.dart';
import 'package:quark/utils/error_text.dart';
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
    SlideClipboard? clipboard,
    bool readOnly = false,
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
      clipboard: clipboard,
      readOnly: readOnly,
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

  test('loads at the start slide, clamped to the deck (#2900)', () async {
    for (final (start, selected) in [(2, 's3'), (9, 's3'), (-1, 's1')]) {
      final c = SlideEditorController(
        filePath: 'talks/deck.qslide',
        startIndex: start,
        loadPresentation: (path, {serial}) async => deck(3),
      );
      addTearDown(c.dispose);
      await c.load();
      expect(c.selectedSlideId, selected, reason: 'start $start');
    }
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

  group('read-only (#1170)', () {
    test(
      'a refused save (403) makes the deck read-only and stops retrying',
      () async {
        saveFailure = const ApiException(403, 'save');
        final c = controllerFor(deck(1));
        await c.load();
        expect(c.isReadOnly, isFalse);
        c.addSlide();
        await c.save();
        expect(c.isReadOnly, isTrue);
        expect(c.saveState, SlideSaveState.saved);

        saveFailure = null;
        c.addSlide();
        await c.save();
        expect(saved, isEmpty);
      },
    );

    test('a read-only controller never autosaves', () async {
      final c = controllerFor(deck(1), readOnly: true);
      await c.load();
      expect(c.isReadOnly, isTrue);
      c.addSlide();
      expect(c.saveState, SlideSaveState.saved);
      expect(await c.save(), isTrue);
      expect(saved, isEmpty);
    });

    test('other failures stay failed and editable', () async {
      saveFailure = const ApiException(500, 'save');
      final c = controllerFor(deck(1));
      await c.load();
      c.addSlide();
      await c.save();
      expect(c.isReadOnly, isFalse);
      expect(c.saveState, SlideSaveState.failed);
    });
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

  group('speaker notes (#1166)', () {
    testWidgets('typing is one undo step after a pause, then autosaved', (
      tester,
    ) async {
      final c = controllerFor(deck(2));
      await c.load();
      expect(c.notes, '');
      c.editNotes('Say');
      c.editNotes('Say hello');
      expect(c.notes, 'Say hello', reason: 'the field reads what was typed');
      expect(
        c.slides.first.notes,
        '',
        reason: 'not committed before the pause',
      );
      expect(c.saveState, SlideSaveState.dirty);
      expect(c.canUndo, isTrue);

      await tester.pump(SlideEditorController.notesDelay);
      expect(c.slides.first.notes, 'Say hello');
      await tester.pump(const Duration(seconds: 2));
      expect(saved.single.slides.first.notes, 'Say hello');

      c.undo();
      expect(c.slides.first.notes, '');
      expect(c.notes, '');
      c.redo();
      expect(c.notes, 'Say hello');
      await tester.pump(const Duration(seconds: 2));
    });

    test('undo inside the pause takes the typing back', () async {
      final c = controllerFor(deck(1));
      await c.load();
      c.editNotes('Draft');
      c.undo();
      expect(c.notes, '');
      expect(c.slides.first.notes, '');
      expect(c.canUndo, isFalse);
      c.redo();
      expect(c.notes, 'Draft');
    });

    test(
      'showing another slide commits the notes to the slide typed on',
      () async {
        final c = controllerFor(deck(2));
        await c.load();
        c.editNotes('First');
        c.selectSlide('s2');
        expect(c.slides.first.notes, 'First');
        expect(c.notes, '');
        c.editNotes('Second');
        expect(await c.save(), isTrue);
        expect(saved.single.slides.last.notes, 'Second');
      },
    );

    testWidgets('leaving inside the pause saves the typing', (tester) async {
      final c = controllerFor(deck(1), disposeAtEnd: false);
      await c.load();
      c.editNotes('Last words');
      c.dispose();
      await tester.pump();
      expect(saved.single.slides.single.notes, 'Last words');
    });

    test('the notes panel opens and closes', () async {
      final c = controllerFor(deck(1));
      await c.load();
      expect(c.notesOpen, isFalse);
      c.toggleNotes();
      expect(c.notesOpen, isTrue);
      c.toggleNotes();
      expect(c.notesOpen, isFalse);
    });
  });

  group('toolbar and properties panel (#1167)', () {
    ElementFrame box(double x, double y) =>
        ElementFrame(x: x, y: y, width: 200, height: 100);

    Presentation drawn() => Presentation(
      title: 'Deck',
      slides: [
        Slide(
          id: 's1',
          elements: [
            ShapeElement(id: 'shape', frame: box(100, 100)),
            LineElement(id: 'line', frame: box(400, 100)),
            TextBox(
              id: 'text',
              frame: box(100, 400),
              paragraphs: const [
                TextParagraph([TextRun('Hello')]),
              ],
            ),
            ImageElement(id: 'pic', frame: box(400, 400), source: 'a.png'),
          ],
        ),
        Slide(id: 's2'),
      ],
    );

    SlideElement element(SlideEditorController c, String id) =>
        c.selectedSlide!.elements.firstWhere((e) => e.id == id);

    test('restyles the selected shapes and lines as one undo step', () async {
      final c = controllerFor(drawn());
      await c.load();
      c.selectElements({'shape', 'line', 'text'});
      expect(c.hasShapesOrLines, isTrue);

      c.styleSelection(const ElementStyle(strokeColor: SlideColor(0xFFFF0000)));

      expect(
        (element(c, 'shape') as ShapeElement).stroke?.color,
        const SlideColor(0xFFFF0000),
      );
      expect(
        (element(c, 'line') as LineElement).stroke.color,
        const SlideColor(0xFFFF0000),
      );
      expect(c.selectionStyle.strokeColor, const SlideColor(0xFFFF0000));
      expect(c.saveState, SlideSaveState.dirty);
      c.undo();
      expect((element(c, 'shape') as ShapeElement).stroke, isNull);
      expect(c.canUndo, isFalse);
    });

    test(
      'formats the selected text boxes through the text controller',
      () async {
        final c = controllerFor(drawn());
        await c.load();
        expect(c.textEditing.canFormat, isFalse);
        c.selectElements({'text'});
        expect(c.textEditing.canFormat, isTrue);

        c.textEditing.toggle(TextToggle.bold);

        final run =
            (element(c, 'text') as TextBox).paragraphs.single.runs.single;
        expect(run.bold, isTrue);
        expect(c.textEditing.selectionFormat.bold, isTrue);
        c.undo();
        expect(
          (element(c, 'text') as TextBox).paragraphs.single.runs.single.bold,
          isFalse,
        );
      },
    );

    test('steps the font size through the sizes the toolbar offers', () async {
      final c = controllerFor(drawn());
      await c.load();
      c.selectElements({'text'});
      expect(c.fontSize, SlideEditorController.inheritedFontSize);

      c.stepFontSize(1);
      expect(c.fontSize, 40);
      c.stepFontSize(-1);
      c.stepFontSize(-1);
      expect(c.fontSize, 32);
      c.setFontSize(500);
      expect(c.fontSize, SlideEditorController.maxFontSize);
      c.setFontSize(1);
      expect(c.fontSize, SlideEditorController.minFontSize);
    });

    test('moves the selection in the stacking order', () async {
      final c = controllerFor(drawn());
      await c.load();
      c.selectElements({'shape'});
      c.arrange(ZOrderMove.toFront);
      expect(c.selectedSlide!.elements.last.id, 'shape');
      c.arrange(ZOrderMove.backward);
      expect(c.selectedSlide!.elements[2].id, 'shape');
    });

    test('deletes the selection in one step', () async {
      final c = controllerFor(drawn());
      await c.load();
      c.selectElements({'shape', 'pic'});
      c.deleteSelection();
      expect(
        [for (final e in c.selectedSlide!.elements) e.id],
        ['line', 'text'],
      );
      expect(c.selectedElementIds, isEmpty);
      c.undo();
      expect(c.selectedSlide!.elements, hasLength(4));
    });

    test('duplicates the selection, offset, and selects the copies', () async {
      final c = controllerFor(drawn());
      await c.load();
      c.selectElements({'shape', 'line'});
      c.duplicateSelection();

      final elements = c.selectedSlide!.elements;
      expect(elements, hasLength(6));
      final copies = elements.sublist(4);
      expect({for (final e in copies) e.id}, c.selectedElementIds);
      expect(c.selectedElementIds.intersection({'shape', 'line'}), isEmpty);
      expect(copies.first.frame.x, 100 + SlideDocumentController.pasteOffset);
      // A second duplicate lands past the first, not on top of it.
      c.duplicateSelection();
      expect(
        c.selectedElements.first.frame.x,
        100 + 2 * SlideDocumentController.pasteOffset,
      );
      c.undo();
      c.undo();
      expect(c.selectedSlide!.elements, hasLength(4));
      expect(c.canUndo, isFalse);
    });

    test('sets one element\'s position, size and rotation, '
        'each as its own step', () async {
      final c = controllerFor(drawn());
      await c.load();
      c.selectElements({'shape'});
      expect(c.singleSelected?.id, 'shape');

      c.setFrame(x: 150);
      c.setFrame(y: 175, width: 300);
      c.setFrame(height: 50, rotation: 45);
      final frame = element(c, 'shape').frame;
      expect(
        [frame.x, frame.y, frame.width, frame.height, frame.rotation],
        [150, 175, 300, 50, 45],
      );
      c.undo();
      expect(element(c, 'shape').frame.rotation, 0);
      expect(element(c, 'shape').frame.height, 100);
      c.undo();
      c.undo();
      expect(element(c, 'shape').frame, box(100, 100));

      c.selectElements({'shape', 'line'});
      expect(c.singleSelected, isNull);
      c.setFrame(x: 0);
      expect(element(c, 'shape').frame.x, 100);
    });

    test('a negative size is kept at zero', () async {
      final c = controllerFor(drawn());
      await c.load();
      c.selectElements({'shape'});
      c.setFrame(width: -5);
      expect(element(c, 'shape').frame.width, 0);
    });

    test('sets an image\'s alt text, and ignores what is unchanged', () async {
      final c = controllerFor(drawn());
      await c.load();
      c.selectElements({'pic'});
      c.setAltText('A dog on a beach');
      expect((element(c, 'pic') as ImageElement).altText, 'A dog on a beach');
      c.setAltText('A dog on a beach');
      c.undo();
      expect((element(c, 'pic') as ImageElement).altText, '');
    });

    test('picks the tool the canvas draws with', () async {
      final c = controllerFor(drawn());
      await c.load();
      c.useTool(const SlideCanvasTool.shape(ShapeKind.star));
      expect(c.tools.tool, const SlideCanvasTool.shape(ShapeKind.star));
    });

    test('opens and closes the properties panel', () async {
      final c = controllerFor(drawn());
      await c.load();
      expect(c.propertiesOpen, isTrue);
      c.toggleProperties();
      expect(c.propertiesOpen, isFalse);
    });
  });

  group('inserting a picture (#1158)', () {
    const picked = (name: 'dog.png', length: 3, bytes: Stream<List<int>>.empty);

    late List<String> uploadedTo;
    late List<double> progress;

    SlideEditorController imageController({
      Future<SlideImageUpload> Function()? upload,
      Future<SlideImageSize?> Function(String path)? size,
      SlideImagePick? pick = picked,
    }) {
      uploadedTo = [];
      progress = [];
      final c = SlideEditorController(
        filePath: 'talks/deck.qslide',
        deviceSerial: 'usb1',
        loadPresentation: (_, {serial}) async => deck(2),
        savePresentation: (_, p, {serial}) async => saved.add(p),
        newId: () => 'img',
        pickImageFile: () async => pick,
        uploadImage:
            (
              path, {
              required name,
              required bytes,
              required length,
              serial,
              onProgress,
            }) async {
              uploadedTo.add('$path $name $length $serial');
              onProgress?.call(0.5);
              return upload == null
                  ? (path: 'talks/dog.png', size: (width: 400.0, height: 300.0))
                  : await upload();
            },
        readImageSize: (path, {serial}) async {
          expect(serial, 'usb1');
          return size == null ? (width: 800.0, height: 600.0) : size(path);
        },
      );
      c.addListener(() {
        final p = c.imageUpload?.progress;
        if (p != null) progress.add(p);
      });
      addTearDown(c.dispose);
      return c;
    }

    test('uploads a picked file beside the presentation and puts it '
        'on the slide at its own shape, selected, as one step', () async {
      final c = imageController();
      await c.load();
      await c.insertImageFromDevice();

      expect(uploadedTo, ['talks/deck.qslide dog.png 3 usb1']);
      expect(progress, contains(0.5));
      expect(c.imageUpload, isNull);
      final image = c.selectedSlide!.elements.single as ImageElement;
      expect(image.source, 'talks/dog.png');
      expect(image.frame.width / image.frame.height, closeTo(4 / 3, 1e-9));
      expect(c.selectedElementIds, {image.id});
      c.undo();
      expect(c.selectedSlide!.elements, isEmpty);
      expect(c.canUndo, isFalse);
    });

    test('a canceled pick does nothing', () async {
      final c = imageController(pick: null);
      await c.load();
      await c.insertImageFromDevice();
      expect(uploadedTo, isEmpty);
      expect(c.canUndo, isFalse);
    });

    test('a failed upload is reported and leaves the slide alone', () async {
      final failure = Exception('offline');
      Object? reported;
      final c = imageController(upload: () async => throw failure);
      c.onImageInsertFailed = (e) => reported = e;
      await c.load();
      await c.insertImageFromDevice();

      expect(reported, same(failure));
      expect(c.imageUpload, isNull);
      expect(c.selectedSlide!.elements, isEmpty);
    });

    test(
      'a picture whose size is unknown goes in at a default shape',
      () async {
        final c = imageController(
          upload: () async => (path: 'talks/odd.png', size: null),
        );
        await c.load();
        await c.insertImageFromDevice();
        final image = c.selectedSlide!.elements.single;
        expect(
          image.frame.width / image.frame.height,
          closeTo(
            SlideEditorController.fallbackImageSize.width /
                SlideEditorController.fallbackImageSize.height,
            1e-9,
          ),
        );
      },
    );

    test('a picture already on the Quark goes in without an upload, '
        'within the box drawn for it', () async {
      final c = imageController();
      await c.load();
      final within = ElementFrame(x: 0, y: 0, width: 100, height: 100);
      await c.insertImageFromQuark('photos/cat.jpg', within: within);

      expect(uploadedTo, isEmpty);
      final image = c.selectedSlide!.elements.single as ImageElement;
      expect(image.source, 'photos/cat.jpg');
      expect(image.frame.width, 100);
      expect(image.frame.height, 75);
    });

    test('the picture lands on the slide it was picked for', () async {
      final gate = Completer<SlideImageUpload>();
      final c = imageController(upload: () => gate.future);
      await c.load();
      final inserting = c.insertImageFromDevice();
      c.selectSlide('s2');
      gate.complete((path: 'talks/dog.png', size: (width: 4.0, height: 3.0)));
      await inserting;

      expect(c.slides.first.elements, hasLength(1));
      expect(c.slides.last.elements, isEmpty);
      // Nothing is selected on the slide showing now.
      expect(c.selectedElementIds, isEmpty);
    });
  });

  group('export to PowerPoint (#1172)', () {
    late List<String> events;
    late Object? exportFailure;

    SlideEditorController exportController() {
      final controller = SlideEditorController(
        filePath: 'talks/Quarterly review.qslide',
        deviceSerial: 'usb1',
        loadPresentation: (_, {serial}) async => deck(2),
        savePresentation: (path, p, {serial}) async {
          final failure = saveFailure;
          if (failure != null) throw failure;
          events.add('save');
        },
        exportPresentation: (path, {serial, required fileName}) async {
          final failure = exportFailure;
          if (failure != null) throw failure;
          events.add('export $path $serial $fileName');
          return '/downloads/$fileName';
        },
        newId: () => 'n${events.length}',
      );
      addTearDown(controller.dispose);
      return controller;
    }

    setUp(() {
      events = [];
      exportFailure = null;
    });

    test('exports the saved presentation under its own name', () async {
      final c = exportController();
      await c.load();
      await c.exportPptx();
      expect(events, [
        'export talks/Quarterly review.qslide usb1 Quarterly review.pptx',
      ]);
      expect(c.isExporting, isFalse);
    });

    test('saves unsaved edits first', () async {
      final c = exportController();
      await c.load();
      c.addSlide();
      expect(c.saveState, SlideSaveState.dirty);
      await c.exportPptx();
      expect(events, [
        'save',
        'export talks/Quarterly review.qslide usb1 Quarterly review.pptx',
      ]);
      expect(c.saveState, SlideSaveState.saved);
    });

    test('a failed save stops the export, which would be stale', () async {
      final c = exportController();
      final exportErrors = <Object>[];
      c.onExportFailed = exportErrors.add;
      await c.load();
      c.addSlide();
      saveFailure = Exception('offline');
      await c.exportPptx();
      expect(events, isEmpty);
      // The save reports its own failure; the export adds nothing.
      expect(exportErrors, isEmpty);
      expect(c.isExporting, isFalse);
    });

    test('a failed export is reported as the thrown object', () async {
      final c = exportController();
      final exportErrors = <Object>[];
      c.onExportFailed = exportErrors.add;
      await c.load();
      final failure = Exception('500');
      exportFailure = failure;
      await c.exportPptx();
      expect(exportErrors, [same(failure)]);
      expect(c.isExporting, isFalse);
    });

    test('a second tap while one is running does nothing', () async {
      final gate = Completer<String?>();
      var calls = 0;
      final c = SlideEditorController(
        filePath: 'talks/deck.qslide',
        loadPresentation: (_, {serial}) async => deck(1),
        exportPresentation: (path, {serial, required fileName}) {
          calls++;
          return gate.future;
        },
      );
      addTearDown(c.dispose);
      await c.load();
      final first = c.exportPptx();
      await Future<void>.delayed(Duration.zero);
      expect(c.isExporting, isTrue);
      await c.exportPptx();
      gate.complete(null);
      await first;
      expect(calls, 1);
      expect(c.isExporting, isFalse);
    });
  });

  group('arrange, clipboard and background (#1174, #1175)', () {
    ElementFrame box(double x, double y) =>
        ElementFrame(x: x, y: y, width: 200, height: 100);

    Presentation drawn() => Presentation(
      title: 'Deck',
      slides: [
        Slide(
          id: 's1',
          elements: [
            ShapeElement(id: 'a', frame: box(100, 100)),
            ShapeElement(id: 'b', frame: box(400, 300)),
            ShapeElement(id: 'c', frame: box(1000, 600)),
          ],
        ),
        Slide(id: 's2'),
      ],
    );

    ElementFrame frameOf(SlideEditorController c, String id) =>
        c.selectedSlide!.findElement(id)!.frame;

    test('says what the selection can be arranged with', () async {
      final c = controllerFor(drawn());
      await c.load();
      expect(
        [c.canGroup, c.canUngroup, c.canAlign, c.canDistribute, c.canMatchSize],
        [false, false, false, false, false],
      );
      c.selectElements({'a'});
      expect(
        [c.canGroup, c.canAlign, c.canDistribute, c.canMatchSize],
        [false, true, false, false],
      );
      c.selectElements({'a', 'b'});
      expect(
        [c.canGroup, c.canAlign, c.canDistribute, c.canMatchSize],
        [true, true, false, true],
      );
      c.selectElements({'a', 'b', 'c'});
      expect(c.canDistribute, isTrue);
    });

    test('groups and ungroups the selection, each as one step', () async {
      final c = controllerFor(drawn());
      await c.load();
      c.selectElements({'a', 'b'});
      c.groupSelection();

      final group = c.singleSelected;
      expect(group, isA<GroupElement>());
      expect(c.canUngroup, isTrue);
      expect(
        [for (final e in c.selectedSlide!.elements) e.id],
        [group!.id, 'c'],
      );
      expect(c.saveState, SlideSaveState.dirty);

      c.ungroupSelection();
      expect(c.selectedElementIds, {'a', 'b'});
      expect(frameOf(c, 'b'), box(400, 300));
      c.undo();
      expect(c.selectedSlide!.elements, hasLength(2));
      c.undo();
      expect(c.selectedSlide!.elements, hasLength(3));
      expect(c.canUndo, isFalse);
    });

    test('aligns the selection, and one element to the slide', () async {
      final c = controllerFor(drawn());
      await c.load();
      c.selectElements({'a', 'b'});
      c.alignSelection(ElementAlignment.left);
      expect(frameOf(c, 'b').x, 100);
      c.alignSelection(ElementAlignment.bottom);
      expect(frameOf(c, 'a').y, 300);

      c.selectElements({'c'});
      c.alignSelection(ElementAlignment.top);
      expect(frameOf(c, 'c').y, 0);

      c
        ..undo()
        ..undo()
        ..undo();
      expect(frameOf(c, 'b'), box(400, 300));
      expect(c.canUndo, isFalse);
    });

    test('distributes and matches sizes as one step each', () async {
      final c = controllerFor(drawn());
      await c.load();
      c.selectElements({'a', 'b', 'c'});
      c.distributeSelection(DistributeAxis.horizontal);
      // Gaps of 250 between 100..300, 550..750 and 1000..1200.
      expect(frameOf(c, 'b').x, 550);

      final wide = c.selectedSlide!.findElement('a')!;
      c.document!.controller.resizeElement(
        's1',
        wide.id,
        width: 500,
        height: 100,
      );
      c.matchSelectionSize(SizeMatch.width);
      expect(frameOf(c, 'c').width, 500);
      c.undo();
      expect(frameOf(c, 'c').width, 200);
    });

    test(
      'copies to and pastes from the clipboard, selecting the paste',
      () async {
        String? text;
        final clipboard = SlideClipboard(
          read: () async => text,
          write: (t) async => text = t,
        );
        final c = controllerFor(drawn(), clipboard: clipboard);
        await c.load();
        c.selectElements({'a'});
        await c.copySelection();
        expect(text, isNotNull);
        expect(c.canUndo, isFalse);

        c.selectSlide('s2');
        await c.paste();
        expect(c.selectedSlide!.elements, hasLength(1));
        expect(c.selectedElementIds, {c.selectedSlide!.elements.single.id});
        expect(c.selectedElements.single.frame, box(100, 100));
        c.undo();
        expect(c.selectedSlide!.elements, isEmpty);
      },
    );

    test('cuts the selection as one step', () async {
      String? text;
      final c = controllerFor(
        drawn(),
        clipboard: SlideClipboard(
          read: () async => text,
          write: (t) async => text = t,
        ),
      );
      await c.load();
      c.selectElements({'a', 'b'});
      await c.cutSelection();
      expect([for (final e in c.selectedSlide!.elements) e.id], ['c']);
      expect(c.selectedElementIds, isEmpty);
      await c.paste();
      expect(c.selectedElementIds, hasLength(2));
      c.undo();
      c.undo();
      expect(c.selectedSlide!.elements, hasLength(3));
    });

    test('pastes plain text as a text box', () async {
      final c = controllerFor(
        drawn(),
        clipboard: SlideClipboard(
          read: () async => 'Hello\nworld',
          write: (_) async {},
        ),
      );
      await c.load();
      await c.paste();
      final pasted = c.singleSelected;
      expect(pasted, isA<TextBox>());
      expect((pasted! as TextBox).paragraphs, hasLength(2));
    });

    test('sets the slide background color as one step', () async {
      final c = controllerFor(drawn());
      await c.load();
      expect(c.slideBackgroundColor, isNull);
      c.setSlideBackgroundColor(const SlideColor(0xFF112233));
      expect(c.slideBackgroundColor, const SlideColor(0xFF112233));
      expect(c.selectedSlide!.background?.color, const SlideColor(0xFF112233));
      expect(c.saveState, SlideSaveState.dirty);

      c.setSlideBackgroundColor(null);
      expect(c.selectedSlide!.background, isNull);
      c.undo();
      c.undo();
      expect(c.selectedSlide!.background, isNull);
      expect(c.canUndo, isFalse);
    });

    test('clearing the color keeps a background picture', () async {
      final c = controllerFor(
        Presentation(
          title: 'Deck',
          slides: [
            Slide(
              id: 's1',
              background: const SlideBackground(
                color: SlideColor(0xFF000000),
                image: 'sky.png',
              ),
            ),
          ],
        ),
      );
      await c.load();
      c.setSlideBackgroundColor(null);
      expect(c.selectedSlide!.background?.image, 'sky.png');
      expect(c.selectedSlide!.background?.color, isNull);
    });
  });

  group('themes and layouts (#1163)', () {
    Presentation titled() => Presentation(
      title: 'Deck',
      slides: [
        Slide(id: 's1', layoutId: SlideLayout.title.id),
        Slide(id: 's2'),
      ],
    );

    test('applies a theme as one undo step that autosaves', () async {
      final c = controllerFor(titled());
      await c.load();
      expect(c.theme, isNull);
      c.applyTheme(SlideThemes.dark);
      expect(c.theme, SlideThemes.dark);
      expect(c.saveState, SlideSaveState.dirty);
      c.applyTheme(null);
      expect(c.theme, isNull);
      c.undo();
      expect(c.theme, SlideThemes.dark);
      c.undo();
      expect(c.theme, isNull);
      expect(c.canUndo, isFalse);
    });

    test('add copies the selected slide\'s layout', () async {
      final c = controllerFor(titled());
      await c.load();
      c.addSlide();
      expect(c.selectedSlide!.layoutId, SlideLayout.title.id);
      expect(c.selectedSlide!.elements, hasLength(2));
      expect(ids(c), ['s1', c.selectedSlideId, 's2']);

      c.selectSlide('s2');
      c.addSlide();
      expect(c.selectedSlide!.layoutId, SlideLayout.blankId);
      expect(c.selectedSlide!.elements, isEmpty);
    });

    test('add with a layout builds the slide on it', () async {
      final c = controllerFor(titled());
      await c.load();
      c.addSlide(layoutId: SlideLayout.twoContent.id);
      expect(c.selectedIndex, 1);
      expect(c.selectedLayoutId, SlideLayout.twoContent.id);
      c.undo();
      expect(ids(c), ['s1', 's2']);
    });

    test('changes and resets the selected slide\'s layout', () async {
      final c = controllerFor(titled());
      await c.load();
      c.setSlideLayout(SlideLayout.titleAndContent.id);
      expect(c.selectedLayoutId, SlideLayout.titleAndContent.id);
      final body = c.selectedSlide!.elements.whereType<TextBox>().last;
      c.document!.controller.moveElements('s1', {body.id}, 50, 50);
      c.resetSlideToLayout();
      expect(c.selectedSlide!.findElement(body.id)!.frame, body.frame);
      c
        ..undo()
        ..undo()
        ..undo();
      expect(c.selectedLayoutId, SlideLayout.title.id);
      expect(c.canUndo, isFalse);
    });
  });
  group('transitions (#1164)', () {
    const fade = SlideTransitionSpec.fade(durationMs: 800);

    test('a slide follows the deck until it is given its own', () async {
      final c = controllerFor(
        Presentation(
          title: 'Deck',
          defaultTransition: fade,
          slides: [
            Slide(id: 's1'),
            Slide(id: 's2'),
          ],
        ),
      );
      await c.load();
      expect(c.slideTransition, isNull);
      expect(c.effectiveTransition, fade);

      const push = SlideTransitionSpec(kind: SlideTransitionKind.push);
      c.setSlideTransition(push);
      expect(c.slideTransition, push);
      expect(c.effectiveTransition, push);
      expect(c.saveState, SlideSaveState.dirty);

      c.undo();
      expect(c.slideTransition, isNull);
      expect(c.effectiveTransition, fade);
      expect(c.canUndo, isFalse);
    });

    test('apply to all sets the deck default as one undo step', () async {
      final c = controllerFor(deck(2));
      await c.load();
      c.setSlideTransition(const SlideTransitionSpec.fade());
      c.applyTransitionToAll(fade);
      expect(c.presentation!.defaultTransition, fade);
      expect(c.slides.every((s) => s.transition == null), isTrue);
      c.undo();
      expect(c.presentation!.defaultTransition, SlideTransitionSpec.none);
      expect(c.slideTransition, const SlideTransitionSpec.fade());
    });

    test('a view-only deck ignores transition changes', () async {
      final c = controllerFor(deck(1), readOnly: true);
      await c.load();
      c.setSlideTransition(fade);
      c.applyTransitionToAll(fade);
      expect(c.slideTransition, isNull);
      expect(c.presentation!.defaultTransition, SlideTransitionSpec.none);
      expect(c.canUndo, isFalse);
    });

    test('nothing is selected before the load', () {
      final c = controllerFor(deck(1));
      expect(c.slideTransition, isNull);
      expect(c.effectiveTransition, SlideTransitionSpec.none);
      c.setSlideTransition(fade);
      c.applyTransitionToAll(fade);
    });
  });

  group('tables (#1160)', () {
    Future<SlideEditorController> withTable({bool readOnly = false}) async {
      final c = controllerFor(deck(1), readOnly: readOnly);
      await c.load();
      if (!readOnly) c.insertTable(3, 3);
      return c;
    }

    TableElement table(SlideEditorController c) =>
        c.selectedSlide!.elements.whereType<TableElement>().single;

    test('inserting a table puts it in the middle, selected, as one '
        'undo step that starts the autosave', () async {
      final c = await withTable();
      final t = table(c);
      expect((t.rowCount, t.columnCount), (3, 3));
      expect(c.selectedElementIds, {t.id});
      expect(c.selectedTable, same(t));
      expect(c.tools.tool, SlideCanvasTool.select);
      expect(c.saveState, SlideSaveState.dirty);
      final slide = c.presentation!.size;
      expect(t.frame.x + t.frame.width / 2, closeTo(slide.width / 2, 1));
      c.undo();
      expect(c.selectedSlide!.elements, isEmpty);
      expect(c.selectedTable, isNull);
      expect(c.canUndo, isFalse);
    });

    test('the insert size is kept within 1 and the table limits', () async {
      final c = controllerFor(deck(1));
      await c.load();
      c.insertTable(0, 200);
      final t = table(c);
      expect(t.rowCount, 1);
      expect(t.columnCount, TableElement.maxColumns);
    });

    test(
      'with the whole table selected, the commands act on all of it',
      () async {
        final c = await withTable();
        expect(c.tables.hasSelection, isFalse);
        expect(c.canEditTable, isTrue);

        c.insertTableRowBelow();
        expect(table(c).rowCount, 4);
        c.insertTableColumnRight();
        expect(table(c).columnCount, 4);
        expect(c.canDeleteTableRows, isFalse, reason: 'the Delete key does');
        expect(c.canMergeTableCells, isFalse);

        c.setTableStyle(headerRow: false, bandedRows: false);
        expect(table(c).headerRow, isFalse);
        expect(table(c).bandedRows, isFalse);

        const red = SlideColor(0xFFFF0000);
        c.formatTableCells(const CellFormat(fill: red));
        expect(c.tableCellFill, red);
        for (final row in table(c).cells) {
          expect(row.every((cell) => cell.fill == red), isTrue);
        }

        c.formatTableCells(const CellFormat(borders: CellBorderPreset.none));
        expect(table(c).cell(1, 1).borders, const CellBorders());

        c.undo();
        expect(table(c).cell(1, 1).borders, isNot(const CellBorders()));
        await c.save();
      },
    );

    test(
      'distributing evens the rows and columns as one undo step each',
      () async {
        final c = await withTable();
        final id = table(c).id;
        final slideId = c.selectedSlideId!;
        c.document!.controller.setTableColumnWidth(slideId, id, 0, 500);
        c.document!.controller.setTableRowHeight(slideId, id, 2, 200);
        final width = table(c).frame.width;
        final height = table(c).frame.height;

        c.distributeTableColumns();
        for (final w in table(c).columnWidths) {
          expect(w, closeTo(width / 3, 0.01));
        }
        expect(table(c).frame.width, closeTo(width, 0.01));
        c.distributeTableRows();
        for (final h in table(c).rowHeights) {
          expect(h, closeTo(height / 3, 0.01));
        }
        c.undo();
        expect(table(c).rowHeights[2], 200);
        expect(table(c).columnWidths.first, closeTo(width / 3, 0.01));
        c.undo();
        expect(table(c).columnWidths.first, 500);
        await c.save();
      },
    );

    test('with cells selected, the commands act on those cells', () async {
      final c = await withTable();
      final id = table(c).id;
      c.tables.select(
        id,
        const CellRange(top: 1, left: 0, bottom: 1, right: 1),
      );
      expect(c.canDeleteTableRows, isTrue);
      expect(c.canMergeTableCells, isTrue);
      expect(c.canUnmergeTableCells, isFalse);

      c.mergeTableCells();
      expect(table(c).cell(1, 0).colSpan, 2);
      expect(c.canUnmergeTableCells, isTrue);
      c.unmergeTableCells();
      expect(table(c).cell(1, 0).colSpan, 1);

      c.insertTableRowAbove();
      expect(table(c).rowCount, 4);
      expect(c.tables.range?.top, 2, reason: 'the selection moved down');
      c.insertTableColumnLeft();
      expect(table(c).columnCount, 4);
      c.deleteTableColumns();
      expect(table(c).columnCount, 2, reason: 'both selected columns');
      expect(c.tables.range, const CellRange.single(2, 1));
      c.deleteTableRows();
      expect(table(c).rowCount, 3);

      final slideId = c.selectedSlideId!;
      c.document!.controller.setTableColumnWidth(slideId, id, 0, 100);
      c.tables.select(id, const CellRange.single(0, 0));
      c.distributeTableColumns();
      final widths = table(c).columnWidths;
      expect(
        widths.first,
        closeTo(widths.last, 0.01),
        reason: 'one column selected evens the whole table',
      );
      await c.save();
    });

    test('the text controls format the selected cells', () async {
      final c = await withTable();
      final id = table(c).id;
      c.document!.controller.setCellText(c.selectedSlideId!, id, 1, 1, [
        TextParagraph.plain('Revenue'),
      ]);
      c.tables.select(id, const CellRange.single(1, 1));
      expect(c.canFormatText, isTrue);
      expect(TextToggle.bold.isOn(c.textFormat), isFalse);

      c.toggleText(TextToggle.bold);
      expect(table(c).cell(1, 1).paragraphs.single.runs.single.bold, isTrue);
      expect(TextToggle.bold.isOn(c.textFormat), isTrue);
      expect(
        table(c).cell(1, 2).paragraphs.isEmpty ||
            table(c).cell(1, 2).plainText.isEmpty,
        isTrue,
      );

      c.formatText(const TextFormat(alignment: TextAlignment.center));
      expect(
        table(c).cell(1, 1).paragraphs.single.alignment,
        TextAlignment.center,
      );
      c.setFontSize(40);
      expect(c.fontSize, 40);
      await c.save();
    });

    test('a table selection only counts while the table is selected', () async {
      final c = await withTable();
      final id = table(c).id;
      c.tables.select(id, const CellRange.single(0, 0));
      c.selectElements({});
      expect(c.tables.hasSelection, isFalse);
      expect(c.canEditTable, isFalse);
      expect(c.selectedTable, isNull);
      await c.save();
    });

    test('a view-only deck changes no table', () async {
      final c = controllerFor(
        Presentation(
          title: 'Deck',
          slides: [
            Slide(
              id: 's1',
              elements: [
                newTable(
                  id: 't',
                  frame: ElementFrame(x: 0, y: 0, width: 600, height: 240),
                  rows: 3,
                  columns: 2,
                ),
              ],
            ),
          ],
        ),
        readOnly: true,
      );
      await c.load();
      c.selectElements({'t'});
      expect(c.canEditTable, isFalse);
      c.insertTable(2, 2);
      c.insertTableRowBelow();
      c.setTableStyle(headerRow: false);
      c.formatTableCells(const CellFormat(fill: SlideColor(0xFF000000)));
      c.distributeTableRows();
      expect(c.selectedSlide!.elements, hasLength(1));
      expect(table(c).rowCount, 3);
      expect(table(c).headerRow, isTrue);
      expect(c.canUndo, isFalse);
    });
  });

  group('charts (#1160)', () {
    // The chart editing controller schedules its notices after a frame.
    TestWidgetsFlutterBinding.ensureInitialized();

    Future<SlideEditorController> withChart({
      ChartKind kind = ChartKind.bar,
    }) async {
      final c = controllerFor(deck(1));
      await c.load();
      c.insertChart(kind);
      return c;
    }

    ChartElement chart(SlideEditorController c) =>
        c.selectedSlide!.elements.whereType<ChartElement>().single;

    test('inserting a chart puts sample data in the middle, selected, as '
        'one undo step that starts the autosave', () async {
      final c = await withChart(kind: ChartKind.line);
      final ch = chart(c);
      expect(ch.kind, ChartKind.line);
      expect(ch.data, SlideDocumentController.sampleChartData(ChartKind.line));
      expect(c.selectedElementIds, {ch.id});
      expect(c.selectedChart, same(ch));
      expect(c.canEditChart, isTrue);
      expect(c.charts.chart, same(ch), reason: 'the toolbar sees it at once');
      expect(c.charts.canEdit, isTrue);
      expect(c.tools.tool, SlideCanvasTool.select);
      expect(c.saveState, SlideSaveState.dirty);
      final slide = c.presentation!.size;
      expect(ch.frame.x + ch.frame.width / 2, closeTo(slide.width / 2, 1));
      expect(ch.frame.y + ch.frame.height / 2, closeTo(slide.height / 2, 1));
      c.undo();
      expect(c.selectedSlide!.elements, isEmpty);
      expect(c.selectedChart, isNull);
      expect(c.canUndo, isFalse);
    });

    test('kind, title, legend, labels and gridlines are one undo step '
        'each', () async {
      final c = await withChart();
      c.setChartKind(ChartKind.pie);
      expect(chart(c).kind, ChartKind.pie);
      c.setChartOptions(title: 'Sales');
      c.setChartOptions(showLegend: false);
      c.setChartOptions(showDataLabels: true);
      c.setChartOptions(showGridlines: false);
      final options = chart(c).options;
      expect(options.title, 'Sales');
      expect(options.showLegend, isFalse);
      expect(options.showDataLabels, isTrue);
      expect(options.showGridlines, isFalse);

      c.undo();
      expect(chart(c).options.showGridlines, isTrue);
      expect(chart(c).options.showDataLabels, isTrue);
      c.undo();
      c.undo();
      c.undo();
      expect(chart(c).options.title, isEmpty);
      expect(chart(c).kind, ChartKind.pie);
      c.undo();
      expect(chart(c).kind, ChartKind.bar);
    });

    test('a series color is set by index, the rest keep theirs, and the '
        'theme colors come back', () async {
      final c = await withChart();
      const red = SlideColor(0xFFFF0000);
      c.setChartSeriesColor(1, red);
      expect(chart(c).colorOf(1), red);
      expect(chart(c).colorOf(0), ChartElement.defaultPalette[0]);
      c.setChartSeriesColor(1, null);
      expect(chart(c).colors, isEmpty, reason: 'back to the theme accents');
      c.setChartSeriesColor(0, red);
      c.setChartColors(const []);
      expect(chart(c).colors, isEmpty);
      c.undo();
      expect(chart(c).colorOf(0), red);
    });

    test('a data grid replaces the numbers as one undo step', () async {
      final c = await withChart();
      final before = chart(c).data;
      c.setChartDataGrid(const [
        ['', 'Revenue', 'Costs'],
        ['Q1', '12', '8'],
        ['Q2', '30', ''],
        ['Q3', '1,200', '9'],
      ]);
      final data = chart(c).data;
      expect(data.categories, ['Q1', 'Q2', 'Q3']);
      expect(data.series.map((s) => s.name), ['Revenue', 'Costs']);
      expect(data.series[1].values, [8, 0, 9]);
      expect(data.series[0].values.last, 1200);
      c.undo();
      expect(chart(c).data, before);
    });

    test('a grid past the limits throws and changes nothing', () async {
      final c = await withChart();
      final before = c.presentation;
      expect(
        () => c.setChartDataGrid([
          ['', for (var i = 0; i <= ChartData.maxSeries; i++) 'S$i'],
          ['Q1', for (var i = 0; i <= ChartData.maxSeries; i++) '1'],
        ]),
        throwsArgumentError,
      );
      expect(c.presentation, same(before));
    });

    test('a view-only deck reports the chart but changes nothing', () async {
      final c = controllerFor(
        Presentation(
          title: 'Deck',
          slides: [
            Slide(
              id: 's1',
              elements: [
                ChartElement(
                  id: 'ch',
                  frame: ElementFrame(x: 0, y: 0, width: 600, height: 400),
                  data: SlideDocumentController.sampleChartData(ChartKind.bar),
                ),
              ],
            ),
          ],
        ),
        readOnly: true,
      );
      await c.load();
      c.selectElements({'ch'});
      expect(c.selectedChart, isNotNull);
      expect(c.charts.chart, isNotNull);
      expect(c.canEditChart, isFalse);
      expect(c.charts.canEdit, isFalse);
      final before = c.presentation;
      c
        ..insertChart(ChartKind.pie)
        ..setChartKind(ChartKind.pie)
        ..setChartOptions(title: 'x')
        ..setChartSeriesColor(0, const SlideColor(0xFF000000))
        ..setChartDataGrid(const [
          ['', 'A'],
          ['Q1', '1'],
        ]);
      expect(c.presentation, same(before));
      expect(c.canUndo, isFalse);
    });

    test('selecting something else lets go of the chart', () async {
      final c = await withChart();
      c.selectElements(const {});
      expect(c.selectedChart, isNull);
      expect(c.charts.hasChart, isFalse);
      expect(c.canEditChart, isFalse);
    });
  });
}
