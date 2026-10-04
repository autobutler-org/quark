import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

import '../support/canvas_harness.dart';

/// A clipboard of its own, so tests do not share [SlideClipboard.memory].
SlideClipboard scratch([String? initial]) {
  var text = initial;
  return SlideClipboard(
    read: () async => text,
    write: (value) async => text = value,
  );
}

void main() {
  late SlideDocumentNotifier doc;
  setUp(() => doc = SlideDocumentNotifier(canvasDeck()));
  tearDown(() => doc.dispose());

  Slide slide() => doc.presentation.slideById('s')!;
  List<String> topIds() => [for (final e in slide().elements) e.id];

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    // Clipboard reads and writes finish in microtasks.
    await tester.pump();
    await tester.pump();
  }

  /// Selects `box` and `ball`, then groups them with Ctrl+G.
  Future<String> groupBoxAndBall(WidgetTester tester) async {
    await tester.tap(elementKey('box'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(elementKey('ball'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await press(tester, LogicalKeyboardKey.keyG);
    return harness(tester).selection.single;
  }

  /// Drags from the slide point [from] by [by] slide units, Alt held so
  /// nothing snaps.
  Future<void> drag(WidgetTester tester, Offset from, Offset by) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final gesture = await tester.startGesture(slideToGlobal(tester, from));
    for (var i = 1; i <= 4; i++) {
      await gesture.moveTo(slideToGlobal(tester, from + by * (i / 4)));
      await tester.pump();
    }
    await gesture.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
  }

  group('grouping', () {
    testBothViewports('Ctrl+G groups, Ctrl+Shift+G ungroups, a step each',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      final id = await groupBoxAndBall(tester);
      expect(slide().elementById(id), isA<GroupElement>());
      expect(topIds(), ['title', id, 'pic']);
      // The children are still drawn, keyed as before.
      expect(elementKey('box'), findsOneWidget);
      expect(handleKey(SlideHandle.bottomRight), findsOneWidget);
      await press(tester, LogicalKeyboardKey.keyG, shift: true);
      expect(harness(tester).selection, {'box', 'ball'});
      expect(topIds(), ['title', 'box', 'ball', 'pic']);
      expect(undoAll(doc), 2);
      expect(tester.takeException(), isNull);
    });

    testBothViewports('a group drags as one, in one undo step',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      final id = await groupBoxAndBall(tester);
      await drag(tester, const Offset(500, 625), const Offset(100, 50));
      expect(frameOf(doc, id).x, closeTo(300, 1));
      expect(slide().frameOnSlide('ball')!.x, closeTo(1400, 1));
      expect(slide().frameOnSlide('box')!.y, closeTo(450, 1));
      expect(harness(tester).selection, {id});
      expect(undoAll(doc), 2);
    });

    testBothViewports('a group resizes as one, scaling its children',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      final id = await groupBoxAndBall(tester);
      final before = frameOf(doc, id);
      final corner = tester.getCenter(handleKey(SlideHandle.bottomRight));
      final scale = canvasViewport(tester).scale;
      final gesture = await tester.startGesture(corner);
      await gesture.moveBy(Offset(-750 * scale / 2, 0));
      await gesture.moveBy(Offset(-750 * scale / 2, 0));
      await gesture.up();
      await tester.pump();
      final after = frameOf(doc, id);
      expect(after.width, closeTo(before.width - 750, 2));
      // The ball keeps its share of the group.
      final ball = slide().frameOnSlide('ball')!;
      expect(ball.width, closeTo(400 * after.width / before.width, 1));
      expect(undoAll(doc), 2);
    });

    testBothViewports('double tap enters, Escape leaves, a child drags alone',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      final id = await groupBoxAndBall(tester);
      await doubleTap(tester, slideToGlobal(tester, const Offset(1500, 650)));
      expect(harness(tester).selection, {'ball'});
      // Handles follow the child, not the group.
      final handle = tester.getCenter(handleKey(SlideHandle.bottomRight));
      expect(handle.dx,
          closeTo(slideToGlobal(tester, const Offset(1700, 850)).dx, 1));
      // Far enough to pass touch slop on a phone.
      await drag(tester, const Offset(1500, 650), const Offset(-300, 0));
      expect(slide().frameOnSlide('ball')!.x, closeTo(1000, 1));
      expect(slide().frameOnSlide('box')!.x, 200);
      // The group refitted around its moved child.
      expect(frameOf(doc, id).width, closeTo(1200, 1));
      expect(harness(tester).selection, {'ball'});
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(harness(tester).selection, {id});
      // Out of the group, a tap on a child selects the group again.
      await tester.tapAt(slideToGlobal(tester, const Offset(100, 1000)));
      await tester.tapAt(slideToGlobal(tester, const Offset(500, 625)));
      await tester.pump();
      expect(harness(tester).selection, {id});
      expect(tester.takeException(), isNull);
    });

    testBothViewports('Enter enters a selected group from the keyboard',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size);
      final id = await groupBoxAndBall(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(harness(tester).selection, {'box'});
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(harness(tester).selection, {'ball'});
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(slide().frameOnSlide('ball')!.x, 1301);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(harness(tester).selection, {id});
    });

    testBothViewports('a group reads to a screen reader with its children',
        (tester, size) async {
      final semantics = tester.ensureSemantics();
      await pumpCanvas(tester, doc, size: size);
      await groupBoxAndBall(tester);
      expect(find.bySemanticsLabel('Group of 2'), findsOne);
      expect(find.bySemanticsLabel('Ellipse shape'), findsOne);
      semantics.dispose();
    });
  });

  group('clipboard', () {
    testBothViewports('Ctrl+C then Ctrl+V pastes 16 past, then 32',
        (tester, size) async {
      final clipboard = scratch();
      await pumpCanvas(tester, doc, size: size, clipboard: clipboard);
      await tester.tap(elementKey('box'));
      await tester.pump();
      await press(tester, LogicalKeyboardKey.keyC);
      await press(tester, LogicalKeyboardKey.keyV);
      final first = harness(tester).selection.single;
      expect(first, isNot('box'));
      expect(frameOf(doc, first), frameOf(doc, 'box').translate(16, 16));
      await press(tester, LogicalKeyboardKey.keyV);
      final second = harness(tester).selection.single;
      expect(frameOf(doc, second), frameOf(doc, 'box').translate(32, 32));
      expect(elementKey(second), findsOneWidget);
      expect(undoAll(doc), 2);
    });

    testBothViewports('Ctrl+X cuts in one step and Ctrl+V puts it back',
        (tester, size) async {
      final clipboard = scratch();
      await pumpCanvas(tester, doc, size: size, clipboard: clipboard);
      await tester.tap(elementKey('pic'));
      await tester.pump();
      await press(tester, LogicalKeyboardKey.keyX);
      expect(topIds(), ['title', 'box', 'ball']);
      expect(harness(tester).selection, isEmpty);
      await press(tester, LogicalKeyboardKey.keyV);
      final pasted = slide().elementById(harness(tester).selection.single);
      expect(pasted, isA<ImageElement>());
      expect((pasted! as ImageElement).source, 'photos/dog.jpg');
      // Nothing is left where it was, so it lands in its old place.
      expect(
          pasted.frame, ElementFrame(x: 900, y: 900, width: 200, height: 150));
      expect(undoAll(doc), 2);
    });

    testBothViewports('Ctrl+D duplicates a group, one step',
        (tester, size) async {
      await pumpCanvas(tester, doc, size: size, clipboard: scratch());
      final id = await groupBoxAndBall(tester);
      await press(tester, LogicalKeyboardKey.keyD);
      final copy = harness(tester).selection.single;
      expect(slide().elementById(copy), isA<GroupElement>());
      expect(frameOf(doc, copy), frameOf(doc, id).translate(16, 16));
      expect(undoAll(doc), 2);
    });

    testBothViewports('text from another app pastes as a text box',
        (tester, size) async {
      await pumpCanvas(tester, doc,
          size: size, clipboard: scratch('From the web'));
      await tester.tapAt(slideToGlobal(tester, const Offset(100, 1000)));
      await tester.pump();
      await press(tester, LogicalKeyboardKey.keyV);
      final box = slide().elementById(harness(tester).selection.single);
      expect((box! as TextBox).plainText, 'From the web');
      expect(find.text('From the web', findRichText: true), findsOne);
      expect(undoAll(doc), 1);
    });
  });
}
