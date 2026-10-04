import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

import '../support/canvas_harness.dart';

void main() {
  late SlideDocumentNotifier doc;
  setUp(() => doc = SlideDocumentNotifier(canvasDeck()));
  tearDown(() => doc.dispose());

  List<String> ids() =>
      [for (final e in doc.presentation.slideById('s')!.elements) e.id];

  /// The element the last insertion added: the front one.
  SlideElement added() => doc.presentation.slideById('s')!.elements.last;

  /// Drags from the slide point [from] to [to] in a few steps.
  Future<void> drawFrom(WidgetTester tester, Offset from, Offset to) async {
    final gesture = await tester.startGesture(slideToGlobal(tester, from));
    for (var step = 1; step <= 4; step++) {
      await gesture.moveTo(
        slideToGlobal(tester, Offset.lerp(from, to, step / 4)!),
      );
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
  }

  /// Tolerance for a slide coordinate after a round trip through pixels.
  const near = 0.01;

  void expectFrame(ElementFrame frame, Rect expected) {
    expect(frame.x, closeTo(expected.left, near), reason: '$frame');
    expect(frame.y, closeTo(expected.top, near), reason: '$frame');
    expect(frame.width, closeTo(expected.width, near), reason: '$frame');
    expect(frame.height, closeTo(expected.height, near), reason: '$frame');
  }

  group('shape tool', () {
    testBothViewports('a drag draws the shape, selects it, as one step',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      harness(tester).useTool(const SlideCanvasTool.shape(ShapeKind.star));
      await tester.pump();
      // Starting over an element draws rather than selecting it.
      await drawFrom(tester, const Offset(300, 450), const Offset(700, 650));
      final shape = added() as ShapeElement;
      expect(shape.kind, ShapeKind.star);
      expect(shape.fill, SlideDocumentController.defaultShapeFill);
      expectFrame(shape.frame, const Rect.fromLTRB(300, 450, 700, 650));
      expect(harness(tester).selection, {shape.id});
      expect(harness(tester).tool, SlideCanvasTool.select);
      expect(frameOf(doc, 'box'), canvasDeck().slides.single.elements[1].frame);
      expect(undoAll(doc), 1);
      expect(tester.takeException(), isNull);
    });

    testBothViewports('a click places one at the default size',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      harness(tester).useTool(const SlideCanvasTool.shape(ShapeKind.ellipse));
      await tester.pump();
      await tester.tapAt(slideToGlobal(tester, const Offset(1000, 100)));
      await tester.pump();
      const side = SlideDocumentController.defaultShapeSize;
      expectFrame(
          added().frame, const Offset(1000, 100) & const Size(side, side));
      expect((added() as ShapeElement).kind, ShapeKind.ellipse);
      expect(undoAll(doc), 1);
    });

    testBothViewports('Shift keeps it square', (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      harness(tester).useTool(const SlideCanvasTool.shape(ShapeKind.rectangle));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await drawFrom(tester, const Offset(300, 300), const Offset(700, 400));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expectFrame(added().frame, const Offset(300, 300) & const Size(400, 400));
    });

    testBothViewports('Alt draws out from the point pressed',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      harness(tester).useTool(const SlideCanvasTool.shape(ShapeKind.triangle));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await drawFrom(tester, const Offset(960, 540), const Offset(1160, 640));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expectFrame(added().frame, const Rect.fromLTRB(760, 440, 1160, 640));
    });

    testBothViewports('the drawn shape is previewed while dragging',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      harness(tester).useTool(const SlideCanvasTool.shape(ShapeKind.diamond));
      await tester.pump();
      final gesture = await tester.startGesture(
        slideToGlobal(tester, const Offset(300, 300)),
      );
      await gesture.moveTo(slideToGlobal(tester, const Offset(600, 500)));
      await tester.pump();
      final preview = find.byKey(const ValueKey('slide_element_'));
      expect(preview, findsOneWidget);
      // Nothing is in the document until the pointer lifts.
      expect(ids(), ['title', 'box', 'ball', 'pic']);
      await gesture.up();
      await tester.pump();
      expect(preview, findsNothing);
      expect(ids(), hasLength(5));
    });

    testWidgets('changing the tool mid-drag drops the drawing', (tester) async {
      await pumpCanvas(tester, doc);
      harness(tester).useTool(const SlideCanvasTool.shape(ShapeKind.star));
      await tester.pump();
      final gesture = await tester.startGesture(
        slideToGlobal(tester, const Offset(300, 300)),
      );
      await gesture.moveTo(slideToGlobal(tester, const Offset(600, 500)));
      await tester.pump();
      harness(tester).useTool(SlideCanvasTool.line);
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(ids(), ['title', 'box', 'ball', 'pic']);
      expect(doc.controller.canUndo, isFalse);
    });
  });

  group('line tool', () {
    testBothViewports('a drag up and right draws a flipped line',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      harness(tester).useTool(SlideCanvasTool.line);
      await tester.pump();
      await drawFrom(tester, const Offset(300, 700), const Offset(700, 300));
      final line = added() as LineElement;
      expectFrame(line.frame, const Rect.fromLTRB(300, 300, 700, 700));
      expect(line.flipped, isTrue);
      expect((line.startCap, line.endCap), (LineCap.none, LineCap.none));
      expect(harness(tester).selection, {line.id});
      expect(undoAll(doc), 1);
    });

    testBothViewports('an arrow points where the drag ended',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      harness(tester).useTool(SlideCanvasTool.arrowLine);
      await tester.pump();
      // Right to left: the arrowhead belongs at the frame's start.
      await drawFrom(tester, const Offset(900, 300), const Offset(500, 300));
      final line = added() as LineElement;
      expectFrame(line.frame, const Rect.fromLTRB(500, 300, 900, 300));
      expect((line.startCap, line.endCap), (LineCap.arrow, LineCap.none));
    });

    testBothViewports('Shift snaps to 45°', (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      harness(tester).useTool(SlideCanvasTool.line);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await drawFrom(tester, const Offset(300, 300), const Offset(700, 330));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      final frame = added().frame;
      expect(frame.height, 0);
      expect(frame.y, closeTo(300, near));
    });

    testBothViewports('a click places a default line', (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      harness(tester).useTool(SlideCanvasTool.arrowLine);
      await tester.pump();
      await tester.tapAt(slideToGlobal(tester, const Offset(1000, 100)));
      await tester.pump();
      const length = SlideDocumentController.defaultLineLength;
      expectFrame(
          added().frame, const Offset(1000, 100) & const Size(length, 0));
      expect((added() as LineElement).endCap, LineCap.arrow);
    });
  });

  group('image tool', () {
    testBothViewports('a click asks for a picture for the default place',
        (tester, size) async {
      final requests = <ElementFrame?>[];
      await pumpCanvas(tester, doc, size: size, onPickImage: requests.add);
      harness(tester).useTool(SlideCanvasTool.image);
      await tester.pump();
      await tester.tapAt(slideToGlobal(tester, const Offset(1000, 100)));
      await tester.pump();
      expect(requests, [null]);
      expect(doc.controller.canUndo, isFalse);
      expect(harness(tester).tool, SlideCanvasTool.select);
    });

    testBothViewports('a drag asks for a picture to fit the box',
        (tester, size) async {
      final requests = <ElementFrame?>[];
      await pumpCanvas(tester, doc, size: size, onPickImage: requests.add);
      harness(tester).useTool(SlideCanvasTool.image);
      await tester.pump();
      await drawFrom(tester, const Offset(100, 100), const Offset(500, 300));
      expect(requests, hasLength(1));
      expectFrame(requests.single!, const Rect.fromLTRB(100, 100, 500, 300));
      expect(doc.controller.canUndo, isFalse);
    });
  });

  group('image resize', () {
    testWidgets('keeps the aspect ratio at an edge and a corner',
        (tester) async {
      await pumpCanvas(tester, doc);
      await tester.tap(elementKey('pic'));
      await tester.pump();
      // pic is 200×150 at (900, 900).
      final right = tester.getCenter(handleKey(SlideHandle.right));
      final scale = canvasViewport(tester).scale;
      await tester.dragFrom(right, Offset(100 * scale, 0));
      await tester.pump();
      var frame = frameOf(doc, 'pic');
      expect(frame.width / frame.height, closeTo(4 / 3, 1e-6));
      final corner = tester.getCenter(handleKey(SlideHandle.bottomRight));
      await tester.dragFrom(corner, Offset(-60 * scale, 10 * scale));
      await tester.pump();
      frame = frameOf(doc, 'pic');
      expect(frame.width / frame.height, closeTo(4 / 3, 1e-6));
    });

    testWidgets('Alt frees the aspect ratio', (tester) async {
      await pumpCanvas(tester, doc);
      await tester.tap(elementKey('pic'));
      await tester.pump();
      final right = tester.getCenter(handleKey(SlideHandle.right));
      final scale = canvasViewport(tester).scale;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.dragFrom(right, Offset(100 * scale, 0));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      final frame = frameOf(doc, 'pic');
      expect(frame.height, 150);
      expect(frame.width, closeTo(300, 0.5));
    });

    testWidgets('a shape still keeps its aspect only with Shift',
        (tester) async {
      await pumpCanvas(tester, doc);
      await tester.tap(elementKey('box'));
      await tester.pump();
      final right = tester.getCenter(handleKey(SlideHandle.right));
      final scale = canvasViewport(tester).scale;
      await tester.dragFrom(right, Offset(100 * scale, 0));
      await tester.pump();
      expect(frameOf(doc, 'box').height, 450);
    });
  });

  group('keyboard', () {
    testBothViewports('Escape returns to select without drawing',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      harness(tester).useTool(SlideCanvasTool.line);
      await tester.pump();
      await tester.tapAt(slideToGlobal(tester, const Offset(10, 10)));
      // That tap drew a line; undo it and try again with the keyboard.
      doc.controller.undo();
      harness(tester).useTool(SlideCanvasTool.line);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(harness(tester).tool, SlideCanvasTool.select);
      expect(ids(), ['title', 'box', 'ball', 'pic']);
    });

    testBothViewports('Enter inserts at the slide center as one step',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      // Give the canvas focus, as a click on it would.
      await tester.tapAt(slideToGlobal(tester, const Offset(10, 10)));
      harness(tester).useTool(const SlideCanvasTool.shape(ShapeKind.star));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      final shape = added() as ShapeElement;
      expect(shape.kind, ShapeKind.star);
      expect(shape.frame.center, const Offset(960, 540));
      expect(harness(tester).selection, {shape.id});
      expect(harness(tester).tool, SlideCanvasTool.select);
      expect(undoAll(doc), 1);
    });

    testWidgets('Enter with the text tool opens a centered box for typing',
        (tester) async {
      final editing = SlideTextEditingController();
      addTearDown(editing.dispose);
      await pumpCanvas(tester, doc, textEditing: editing);
      await tester.tapAt(slideToGlobal(tester, const Offset(10, 10)));
      harness(tester).useTool(SlideCanvasTool.text);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(editing.isEditing, isTrue);
      expect(added(), isA<TextBox>());
      expect(added().frame.center.dx, closeTo(960, near));
    });

    testWidgets('Enter with the image tool asks for a picture', (tester) async {
      final requests = <ElementFrame?>[];
      await pumpCanvas(tester, doc, onPickImage: requests.add);
      await tester.tapAt(slideToGlobal(tester, const Offset(10, 10)));
      harness(tester).useTool(SlideCanvasTool.image);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(requests, [null]);
    });
  });

  group('accessibility', () {
    testBothViewports('a drawing tool labels the canvas, and a tap inserts',
        (tester, size) async {
      final semantics = tester.ensureSemantics();
      await pumpCanvas(tester, doc, size: size);
      expect(find.bySemanticsLabel('Insert star'), findsNothing);
      harness(tester).useTool(const SlideCanvasTool.shape(ShapeKind.star));
      await tester.pump();
      final node = tester.getSemantics(find.bySemanticsLabel('Insert star'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.semantics.tap(find.semantics.byLabel('Insert star'));
      await tester.pump();
      expect((added() as ShapeElement).kind, ShapeKind.star);
      expect(harness(tester).tool, SlideCanvasTool.select);
      expect(find.bySemanticsLabel('Insert star'), findsNothing);
      semantics.dispose();
    });

    testWidgets('an image reads as its alt text', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCanvas(tester, doc);
      doc.controller.setAltText('s', 'pic', 'A dog on a beach');
      await tester.pump();
      expect(find.bySemanticsLabel('Image: A dog on a beach'), findsOneWidget);
      semantics.dispose();
    });

    testBothViewports('200% text scale leaves drawing alone',
        (tester, size) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpCanvas(tester, doc, size: size);
      harness(tester).useTool(SlideCanvasTool.arrowLine);
      await tester.pump();
      await drawFrom(tester, const Offset(300, 300), const Offset(700, 500));
      expectFrame(added().frame, const Rect.fromLTRB(300, 300, 700, 500));
      expect(tester.takeException(), isNull);
    });
  });

  group('drawing', () {
    testWidgets('dashed, translucent shapes and lines paint without error',
        (tester) async {
      final deck = canvasDeck();
      final slide = deck.slides.single;
      final frame = ElementFrame(x: 100, y: 100, width: 300, height: 200);
      final styled = deck.copyWith(
        slides: [
          slide.copyWith(
            elements: [
              for (final kind in ShapeKind.values)
                ShapeElement(
                  id: kind.name,
                  frame: frame,
                  kind: kind,
                  stroke: Stroke(width: 6, dash: StrokeDash.dashDot),
                  cornerRadius: 30,
                  opacity: 0.5,
                ),
              for (final dash in StrokeDash.values)
                LineElement(
                  id: 'line_${dash.name}',
                  frame: frame,
                  stroke: Stroke(width: 8, dash: dash),
                  startCap: LineCap.arrow,
                  endCap: LineCap.arrow,
                  opacity: 0.4,
                ),
            ],
          ),
        ],
      );
      final styledDoc = SlideDocumentNotifier(styled);
      addTearDown(styledDoc.dispose);
      await pumpCanvas(tester, styledDoc);
      expect(
        find.descendant(
          of: elementKey('star'),
          matching: find.byType(Opacity),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
