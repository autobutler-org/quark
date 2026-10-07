import 'package:flutter/gestures.dart';
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

  group('rendering', () {
    testBothViewports('draws every element in a 16:9 letterbox',
        (tester, size) async {
      final requests = <SlideImageSource>[];
      await pumpCanvas(
        tester,
        doc,
        size: size,
        imageBuilder: (context, image) {
          requests.add(image);
          return const ColoredBox(color: Colors.green);
        },
      );
      for (final id in ['title', 'box', 'ball', 'pic']) {
        expect(elementKey(id), findsOneWidget);
      }
      expect(requests, [
        const SlideImageSource('bg.jpg', fit: BoxFit.cover),
        const SlideImageSource('photos/dog.jpg', fit: BoxFit.cover),
      ]);
      final slide = canvasViewport(tester).slideRect;
      expect(slide.width / slide.height, closeTo(16 / 9, 1e-9));
      // The box is placed and scaled with the slide.
      final box = tester.getRect(elementKey('box'));
      final expected = Rect.fromPoints(
        slideToGlobal(tester, const Offset(200, 400)),
        slideToGlobal(tester, const Offset(800, 850)),
      );
      expect(box.left, closeTo(expected.left, 0.01));
      expect(box.width, closeTo(expected.width, 0.01));
      expect(find.text('Quarterly review', findRichText: true), findsOne);
      expect(tester.takeException(), isNull);
    });

    testWidgets('read-only draws the slide in its aspect ratio, no chrome',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: SlideCanvas.readOnly(
                slide: doc.presentation.slides.single,
                size: doc.presentation.size,
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(AspectRatio)), const Size(200, 112.5));
      expect(elementKey('box'), findsOneWidget);
      await tester.tap(elementKey('box'));
      await tester.pump();
      expect(handleKey(SlideHandle.bottomRight), findsNothing);
      expect(doc.controller.canUndo, isFalse);
    });

    testBothViewports('200% text scale leaves slide text and chrome alone',
        (tester, size) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpCanvas(tester, doc, size: size);
      await tester.tap(elementKey('title'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(handleKey(SlideHandle.rotate), findsOneWidget);
      final paragraphs = tester.renderObjectList<RenderParagraph>(
        find.descendant(
          of: elementKey('title'),
          matching: find.byType(RichText),
        ),
      );
      expect(paragraphs, isNotEmpty);
      for (final p in paragraphs) {
        expect(p.textScaler, TextScaler.noScaling);
      }
    });
  });

  group('selection', () {
    testBothViewports('a tap selects an element and shows its handles',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      expect(handleKey(SlideHandle.topLeft), findsNothing);
      await tester.tap(elementKey('box'));
      await tester.pump();
      expect(harness(tester).selection, {'box'});
      for (final handle in SlideHandle.values) {
        expect(handleKey(handle), findsOneWidget, reason: handle.keyName);
      }
      await tester.tapAt(slideToGlobal(tester, const Offset(100, 1000)));
      await tester.pump();
      expect(harness(tester).selection, isEmpty);
      expect(handleKey(SlideHandle.topLeft), findsNothing);
      expect(doc.controller.canUndo, isFalse);
    });

    testBothViewports('Shift adds to and removes from the selection',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      await tester.tap(elementKey('box'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(elementKey('ball'));
      await tester.pump();
      expect(harness(tester).selection, {'box', 'ball'});
      expect(handleKey(SlideHandle.rotate), findsNothing);
      await tester.tap(elementKey('box'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(harness(tester).selection, {'ball'});
    });

    testBothViewports('a tap inside a multi-selection narrows it to one',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      harness(tester).select({'box', 'ball'});
      await tester.pump();
      await tester.tap(elementKey('ball'));
      await tester.pump();
      expect(harness(tester).selection, {'ball'});
    });

    testBothViewports('a marquee selects what it wholly encloses',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      final gesture = await tester.startGesture(
        slideToGlobal(tester, const Offset(100, 350)),
      );
      await gesture.moveTo(slideToGlobal(tester, const Offset(500, 600)));
      await tester.pump();
      expect(harness(tester).selection, isEmpty);
      await gesture.moveTo(slideToGlobal(tester, const Offset(850, 900)));
      await tester.pump();
      expect(harness(tester).selection, {'box'});
      await gesture.up();
      await tester.pump();
      expect(harness(tester).selection, {'box'});
      expect(doc.controller.canUndo, isFalse);
    });

    testBothViewports('each element reads to a screen reader, selected or not',
        (tester, size) async {
      final semantics = tester.ensureSemantics();
      await pumpCanvas(tester, doc, size: size);
      expect(find.bySemanticsLabel('Text box: Quarterly review'), findsOne);
      expect(find.bySemanticsLabel('Image: A dog'), findsOne);
      await tester.tap(elementKey('box'));
      await tester.pump();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Rectangle shape')),
        isSemantics(
          label: 'Rectangle shape',
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Ellipse shape')),
        isSemantics(
          label: 'Ellipse shape',
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      tester.semantics.tap(find.semantics.byLabel('Ellipse shape'));
      await tester.pump();
      expect(harness(tester).selection, {'ball'});
      semantics.dispose();
    });
  });

  group('manipulation', () {
    testBothViewports('dragging moves the selection as one undo step',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      final scale = canvasViewport(tester).scale;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.drag(elementKey('box'), const Offset(30, 20));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(harness(tester).selection, {'box'});
      final frame = frameOf(doc, 'box');
      expect(frame.x, closeTo(200 + 30 / scale, 0.01));
      expect(frame.y, closeTo(400 + 20 / scale, 0.01));
      expect(frameOf(doc, 'ball').x, 1300);
      expect(undoAll(doc), 1);
      expect(frameOf(doc, 'box'),
          ElementFrame(x: 200, y: 400, width: 600, height: 450));
    });

    testBothViewports('dragging a multi-selection moves all of it',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      final scale = canvasViewport(tester).scale;
      harness(tester).select({'box', 'ball'});
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.drag(elementKey('ball'), const Offset(0, 40));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(frameOf(doc, 'box').y, closeTo(400 + 40 / scale, 0.01));
      expect(frameOf(doc, 'ball').y, closeTo(450 + 40 / scale, 0.01));
      expect(undoAll(doc), 1);
    });

    testBothViewports('a drag snaps to the slide center', (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      final scale = canvasViewport(tester).scale;
      // The box's center (500, 625) lands 5 and 3 units off (960, 540).
      final gesture =
          await tester.startGesture(tester.getCenter(elementKey('box')));
      await gesture.moveBy(const Offset(0, 30));
      await gesture.moveBy(Offset(465 * scale, -82 * scale - 30));
      await tester.pump();
      final frame = frameOf(doc, 'box');
      expect(frame.x, closeTo(660, 1e-6));
      expect(frame.y, closeTo(315, 1e-6));
      await gesture.up();
      await tester.pump();
      expect(undoAll(doc), 1);
    });

    testBothViewports('the corner handle resizes as one undo step',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      final scale = canvasViewport(tester).scale;
      await tester.tap(elementKey('box'));
      await tester.pump();
      await tester.drag(
        handleKey(SlideHandle.bottomRight),
        const Offset(40, 30),
      );
      await tester.pump();
      final frame = frameOf(doc, 'box');
      expect(frame.x, 200);
      expect(frame.y, 400);
      expect(frame.width, closeTo(600 + 40 / scale, 0.01));
      expect(frame.height, closeTo(450 + 30 / scale, 0.01));
      expect(harness(tester).selection, {'box'});
      expect(undoAll(doc), 1);
    });

    testBothViewports('the left handle keeps the right edge',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      final scale = canvasViewport(tester).scale;
      await tester.tap(elementKey('box'));
      await tester.pump();
      await tester.drag(handleKey(SlideHandle.left), const Offset(-30, 50));
      final frame = frameOf(doc, 'box');
      expect(frame.x, closeTo(200 - 30 / scale, 0.01));
      expect(frame.x + frame.width, closeTo(800, 0.01));
      expect(frame.height, 450);
    });

    testBothViewports('the rotate handle turns the element toward the pointer',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      await tester.tap(elementKey('box'));
      await tester.pump();
      final gesture = await tester.startGesture(
        tester.getCenter(handleKey(SlideHandle.rotate)),
      );
      await gesture.moveTo(slideToGlobal(tester, const Offset(1000, 625)));
      await gesture.up();
      await tester.pump();
      expect(frameOf(doc, 'box').rotation, closeTo(90, 1e-6));
      expect(undoAll(doc), 1);
    });

    testBothViewports('a second finger turns a drag into a pinch',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      final center = tester.getCenter(elementKey('box'));
      final first = await tester.startGesture(center);
      await first.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(frameOf(doc, 'box').x, isNot(200));
      final second = await tester.startGesture(center + const Offset(60, 0));
      await second.moveBy(const Offset(60, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pump();
      expect(frameOf(doc, 'box').x, 200, reason: 'the drag was taken back');
      expect(harness(tester).zoom, greaterThan(1));
      expect(doc.controller.canUndo, isFalse);
    });
  });

  group('keyboard', () {
    testBothViewports('arrows nudge, Shift by ten, each an undo step',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      await tester.tap(elementKey('box'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(frameOf(doc, 'box').x, 201);
      expect(frameOf(doc, 'box').y, 410);
      expect(undoAll(doc), 2);
    });

    testBothViewports('Delete removes the selection', (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      await tester.tap(elementKey('box'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(doc.presentation.slideById('s')!.elementById('box'), isNull);
      expect(harness(tester).selection, isEmpty);
      expect(elementKey('box'), findsNothing);
    });

    testBothViewports('Tab cycles through the elements, then lets go',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      await tester.tapAt(slideToGlobal(tester, const Offset(100, 1000)));
      final seen = <Set<String>>[];
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        seen.add(harness(tester).selection);
      }
      expect(seen, [
        {'title'},
        {'box'},
        {'ball'},
        {'pic'},
        <String>{},
      ]);
    });

    testBothViewports('Ctrl+Shift+] brings to front, Ctrl+[ sends back',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      List<String> order() =>
          [for (final e in doc.presentation.slideById('s')!.elements) e.id];
      await tester.tap(elementKey('box'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(order(), ['title', 'ball', 'pic', 'box']);
      await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(order(), ['title', 'ball', 'box', 'pic']);
    });
  });

  group('viewport', () {
    testBothViewports('Ctrl-scroll zooms and scroll pans',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      final center = tester.getCenter(find.byType(SlideCanvas));
      await tester.sendEventToBinding(pointer.hover(center));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -500)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(harness(tester).zoom, SlideCanvas.maxZoom);
      // The slide pans along each axis it overflows, and only those.
      final overflow = canvasViewport(tester, zoom: 2).slideRect.size;
      final room = const EdgeInsets.all(24)
          .deflateSize(tester.getSize(find.byType(SlideCanvas)));
      final before = tester.getCenter(elementKey('box'));
      await tester.sendEventToBinding(pointer.scroll(const Offset(50, 50)));
      await tester.pump();
      final moved = tester.getCenter(elementKey('box')) - before;
      expect(moved.dx, closeTo(overflow.width > room.width ? -50 : 0, 0.01));
      expect(moved.dy, closeTo(overflow.height > room.height ? -50 : 0, 0.01));
      expect(moved, isNot(Offset.zero));
      expect(doc.controller.canUndo, isFalse);
    });

    testWidgets('handles show resize cursors to a mouse', (tester) async {
      await pumpCanvas(tester, doc);
      await tester.tap(elementKey('box'));
      await tester.pump();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(handleKey(SlideHandle.bottomRight)));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.resizeUpLeftDownRight,
      );
      await mouse.moveTo(tester.getCenter(elementKey('ball')));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.move,
      );
    });
  });
}
