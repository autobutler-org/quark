import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

import '../support/canvas_harness.dart';
import '../support/table_sample.dart';

/// [canvasDeck] with [sampleTable] moved clear of the other elements, to
/// x 1400, y 880.
Presentation interactionDeck() {
  final deck = canvasDeck();
  final slide = deck.slides.single;
  final table = sampleTable();
  return deck.copyWith(slides: [
    slide.copyWith(elements: [
      ...slide.elements,
      table.withFrame(table.frame.copyWith(x: 1400, y: 880)),
    ]),
  ]);
}

void main() {
  late SlideDocumentNotifier doc;
  setUp(() => doc = SlideDocumentNotifier(interactionDeck()));
  tearDown(() => doc.dispose());

  /// Presses every key that edits, with [selection] selected.
  Future<void> pressEditingKeys(WidgetTester tester) async {
    for (final key in [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.delete,
      LogicalKeyboardKey.backspace,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.f2,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    for (final key in [
      LogicalKeyboardKey.keyX,
      LogicalKeyboardKey.keyV,
      LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.keyG,
      LogicalKeyboardKey.bracketRight,
      LogicalKeyboardKey.bracketLeft,
    ]) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }
  }

  group('selectOnly', () {
    testBothViewports('selects but never edits', (tester, size) async {
      final before = doc.presentation;
      final editing = SlideTextEditingController();
      addTearDown(editing.dispose);
      var clipboardText = '';
      final clipboard = SlideClipboard(
        read: () async => clipboardText,
        write: (text) async => clipboardText = text,
      );
      await pumpCanvas(
        tester,
        doc,
        size: size,
        interaction: SlideCanvasInteraction.selectOnly,
        textEditing: editing,
        clipboard: clipboard,
      );

      // A tap selects, and the selection is outlined without handles.
      await tester.tap(elementKey('box'));
      await tester.pump();
      expect(harness(tester).selection, {'box'});
      for (final handle in SlideHandle.values) {
        expect(handleKey(handle), findsNothing, reason: handle.keyName);
      }

      // A drag neither moves the box nor resizes it from its corner.
      await tester.drag(elementKey('box'), const Offset(60, 40));
      await tester.pump();
      final corner = slideToGlobal(tester, const Offset(800, 850));
      await tester.dragFrom(corner, const Offset(40, 40));
      await tester.pump();

      // Keys that edit do nothing; a double tap opens no editor.
      await pressEditingKeys(tester);
      await doubleTap(tester, slideToGlobal(tester, const Offset(960, 180)));
      expect(editing.isEditing, isFalse);
      expect(harness(tester).selection, {'title'});
      await pressEditingKeys(tester);
      expect(editing.isEditing, isFalse);

      // A drawing tool inserts nothing.
      harness(tester).useTool(const SlideCanvasTool.shape(ShapeKind.star));
      await tester.pump();
      await tester.tapAt(slideToGlobal(tester, const Offset(100, 1000)));
      await tester.pump();

      expect(doc.presentation, same(before));
      expect(doc.controller.canUndo, isFalse);

      // Copy still copies.
      harness(tester).select({'box'});
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(clipboardText, contains('"box"'));
      expect(tester.takeException(), isNull);
    });

    testBothViewports('marquee, Tab and Escape still select',
        (tester, size) async {
      await pumpCanvas(
        tester,
        doc,
        size: size,
        interaction: SlideCanvasInteraction.selectOnly,
      );
      await tester.dragFrom(
        slideToGlobal(tester, const Offset(150, 360)),
        slideToGlobal(tester, const Offset(1750, 870)) -
            slideToGlobal(tester, const Offset(150, 360)),
      );
      await tester.pump();
      expect(harness(tester).selection, {'box', 'ball'});
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(harness(tester).selection, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(harness(tester).selection, {'title'});
      expect(doc.controller.canUndo, isFalse);
    });

    testBothViewports('table cells select but do not edit or clear',
        (tester, size) async {
      final cells = SlideTableEditingController();
      addTearDown(cells.dispose);
      final editing = SlideTextEditingController();
      addTearDown(editing.dispose);
      await pumpCanvas(
        tester,
        doc,
        size: size,
        interaction: SlideCanvasInteraction.selectOnly,
        tableEditing: cells,
        textEditing: editing,
      );
      harness(tester).select({'tbl'});
      await tester.pump();
      expect(find.byKey(const ValueKey('slide_table_column_0')), findsNothing);
      // The middle of the second row's first cell.
      await tester.tapAt(slideToGlobal(tester, const Offset(1450, 940)));
      await tester.pump();
      expect(cells.range, CellRange.single(1, 0));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(cells.range, CellRange.single(1, 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await doubleTap(tester, slideToGlobal(tester, const Offset(1450, 940)));
      expect(editing.isEditing, isFalse);
      expect(doc.controller.canUndo, isFalse);
    });

    testWidgets('a screen reader selects, labels stay, and nothing edits',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final editing = SlideTextEditingController();
      addTearDown(editing.dispose);
      await pumpCanvas(
        tester,
        doc,
        interaction: SlideCanvasInteraction.selectOnly,
        textEditing: editing,
      );
      expect(find.bySemanticsLabel('Quarterly review'), findsOne);
      expect(find.bySemanticsLabel('Image: A dog'), findsOne);
      expect(
        find.bySemanticsLabel('Row 1, column 1: Region'),
        findsOne,
      );
      tester.semantics.tap(find.semantics.byLabel('Quarterly review'));
      await tester.pump();
      expect(harness(tester).selection, {'title'});
      // A second tap on a selected text box edits it when editable; not
      // here.
      tester.semantics.tap(find.semantics.byLabel('Quarterly review'));
      await tester.pump();
      expect(editing.isEditing, isFalse);
      expect(doc.controller.canUndo, isFalse);
      semantics.dispose();
    });

    testWidgets('switching to it ends text editing, keeping what was typed',
        (tester) async {
      final editing = SlideTextEditingController();
      addTearDown(editing.dispose);
      await pumpCanvas(tester, doc, textEditing: editing);
      await doubleTap(tester, slideToGlobal(tester, const Offset(960, 180)));
      expect(editing.isEditing, isTrue);
      await tester.enterText(
        find.byKey(const ValueKey('slide_text_paragraph_0')),
        'Annual review',
      );
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CanvasHarness(
              document: doc,
              textEditing: editing,
              interaction: SlideCanvasInteraction.selectOnly,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(editing.isEditing, isFalse);
      final title = doc.presentation.slides.single.elementById('title');
      expect((title! as TextBox).plainText, 'Annual review');
    });
  });

  group('viewOnly', () {
    testBothViewports('neither selects nor edits, but zooms',
        (tester, size) async {
      final before = doc.presentation;
      await pumpCanvas(
        tester,
        doc,
        size: size,
        interaction: SlideCanvasInteraction.viewOnly,
      );
      await tester.tap(elementKey('box'));
      await tester.pump();
      expect(harness(tester).selection, isEmpty);
      await tester.dragFrom(
        slideToGlobal(tester, const Offset(150, 360)),
        const Offset(300, 200),
      );
      await tester.pump();
      expect(harness(tester).selection, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await pressEditingKeys(tester);
      expect(harness(tester).selection, isEmpty);

      // Ctrl-scroll still zooms.
      final center = tester.getCenter(find.byType(SlideCanvas));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(center));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(harness(tester).zoom, greaterThan(1));

      expect(doc.presentation, same(before));
      expect(doc.controller.canUndo, isFalse);
    });

    testWidgets('ignores a selection it is given and keeps its labels',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCanvas(
        tester,
        doc,
        interaction: SlideCanvasInteraction.viewOnly,
      );
      harness(tester).select({'box'});
      await tester.pump();
      expect(handleKey(SlideHandle.topLeft), findsNothing);
      expect(find.bySemanticsLabel('Rectangle shape'), findsOne);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Rectangle shape')),
        isNot(isSemantics(hasTapAction: true)),
      );
      semantics.dispose();
    });

    testWidgets('a 200% text scale changes nothing', (tester) async {
      await pumpCanvas(
        tester,
        doc,
        size: narrowViewport,
        textScale: 2,
        interaction: SlideCanvasInteraction.viewOnly,
      );
      expect(tester.takeException(), isNull);
      expect(elementKey('tbl'), findsOne);
    });
  });
}
