import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

import '../support/canvas_harness.dart';

/// Taps [global] twice, 100 ms apart, as a double tap.
Future<void> doubleTap(
  WidgetTester tester,
  Offset global, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) async {
  for (final ms in [0, 100]) {
    final gesture = await tester.createGesture(kind: kind);
    await gesture.down(global, timeStamp: Duration(milliseconds: ms));
    await gesture.up(timeStamp: Duration(milliseconds: ms + 20));
    await tester.pump();
  }
  await tester.pump();
}

/// The editor's paragraph field that has focus.
EditableText focusedField(WidgetTester tester) => tester.widget<EditableText>(
      find.byWidgetPredicate((w) => w is EditableText && w.focusNode.hasFocus),
    );

/// Types [text] at the focused field's caret, through the input method.
Future<void> typeText(WidgetTester tester, String text) async {
  final value = focusedField(tester).controller.value;
  final selection = value.selection;
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: value.text.replaceRange(selection.start, selection.end, text),
      selection: TextSelection.collapsed(
        offset: selection.start + text.length,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Finds paragraph [index]'s field.
Finder paragraphKey(int index) =>
    find.byKey(ValueKey('slide_text_paragraph_$index'));

TextBox textBox(SlideDocumentNotifier doc, String id) =>
    doc.presentation.slideById('s')!.elementById(id)! as TextBox;

/// The title's center on screen.
Offset titleCenter(WidgetTester tester) =>
    slideToGlobal(tester, const Offset(960, 180));

void main() {
  late SlideDocumentNotifier doc;
  late SlideTextEditingController editing;
  setUp(() {
    doc = SlideDocumentNotifier(canvasDeck(), newId: () => 'new');
    editing = SlideTextEditingController(fontFamilies: const ['Inter']);
  });
  tearDown(() {
    editing.dispose();
    doc.dispose();
  });

  Future<void> pump(WidgetTester tester, Size size) =>
      pumpCanvas(tester, doc, size: size, textEditing: editing);

  /// Selects the title and presses Enter to edit it.
  Future<void> editTitle(WidgetTester tester) async {
    await tester.tapAt(titleCenter(tester));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
  }

  group('entering edit mode', () {
    testBothViewports('a double tap opens the box under the caret',
        (tester, size) async {
      await pump(tester, size);
      await doubleTap(tester, titleCenter(tester));
      expect(editing.isEditing, isTrue);
      expect(editing.elementId, 'title');
      expect(harness(tester).selection, {'title'});
      expect(paragraphKey(0), findsOne);
      expect(focusedField(tester).controller.text, 'Quarterly review');
      final caret = editing.textSelection;
      expect(caret.isCollapsed, isTrue);
      expect(caret.baseOffset, inInclusiveRange(4, 12),
          reason: 'the caret lands near the middle of the centered text');
      expect(tester.takeException(), isNull);
    });

    testBothViewports('a mouse double-click opens it too',
        (tester, size) async {
      await pump(tester, size);
      await doubleTap(tester, titleCenter(tester),
          kind: PointerDeviceKind.mouse);
      expect(editing.elementId, 'title');
    });

    testBothViewports('Enter and F2 open the selected text box',
        (tester, size) async {
      await pump(tester, size);
      await editTitle(tester);
      expect(editing.elementId, 'title');
      expect(editing.textSelection, const TextSelection.collapsed(offset: 16));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(editing.isEditing, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pump();
      expect(editing.elementId, 'title');
    });

    testBothViewports('Enter on a shape does nothing', (tester, size) async {
      await pump(tester, size);
      await tester.tap(elementKey('box'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(editing.isEditing, isFalse);
    });

    testBothViewports('the editor lies exactly over the box at canvas scale',
        (tester, size) async {
      await pump(tester, size);
      final before = tester.getRect(
        find.descendant(
          of: elementKey('title'),
          matching: find.byType(RichText),
        ),
      );
      await editTitle(tester);
      final field = tester.getRect(find.byType(EditableText));
      expect(field.left, closeTo(before.left, 0.01));
      expect(field.top, closeTo(before.top, 0.01));
      expect(field.height, closeTo(before.height, 0.01));
      // The text inside wraps the same: one line, at the same width.
      final scale = canvasViewport(tester).scale;
      expect(before.width, closeTo(1600 * scale, 0.01));
    });
  });

  group('typing', () {
    testBothViewports('a whole session commits as one undo step',
        (tester, size) async {
      await pump(tester, size);
      await editTitle(tester);
      await typeText(tester, '!');
      await typeText(tester, '!');
      editing.toggle(TextToggle.italic);
      await tester.pump();
      await typeText(tester, '?');
      // Nothing reaches the document until the session ends.
      expect(doc.controller.canUndo, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(editing.isEditing, isFalse);
      final title = textBox(doc, 'title');
      expect(title.plainText, 'Quarterly review!!?');
      expect(title.paragraphs.single.runs.last,
          const TextRun('?', bold: true, italic: true, fontSize: 72));
      expect(undoAll(doc), 1);
      expect(doc.presentation, canvasDeck());
    });

    testBothViewports('a click outside the box commits', (tester, size) async {
      await pump(tester, size);
      await editTitle(tester);
      await typeText(tester, '!');
      await tester.tapAt(slideToGlobal(tester, const Offset(1500, 1000)));
      await tester.pump();
      expect(editing.isEditing, isFalse);
      expect(textBox(doc, 'title').plainText, 'Quarterly review!');
      expect(harness(tester).selection, isEmpty);
    });

    testBothViewports('a click inside the box keeps editing',
        (tester, size) async {
      await pump(tester, size);
      await editTitle(tester);
      await tester.tapAt(titleCenter(tester));
      await tester.pump();
      expect(editing.isEditing, isTrue);
      expect(doc.controller.canUndo, isFalse);
    });

    testBothViewports('ending a session that typed nothing records nothing',
        (tester, size) async {
      await pump(tester, size);
      await editTitle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(doc.controller.canUndo, isFalse);
    });

    testBothViewports('a line break splits the paragraph into a new field',
        (tester, size) async {
      await pump(tester, size);
      await editTitle(tester);
      await typeText(tester, '\nQ3');
      expect(paragraphKey(1), findsOne);
      expect(editing.focusedParagraph, 1);
      expect(editing.draft!.plainText, 'Quarterly review\nQ3');
      await typeText(tester, '!');
      expect(editing.draft!.plainText, 'Quarterly review\nQ3!');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      final title = textBox(doc, 'title');
      expect(title.paragraphs.length, 2);
      expect(title.paragraphs[1].alignment, TextAlignment.center);
      expect(undoAll(doc), 1);
    });

    testBothViewports('backspace at a paragraph start joins it to the last',
        (tester, size) async {
      await pump(tester, size);
      await editTitle(tester);
      await typeText(tester, '\nQ3');
      // The caret goes to the start of the second paragraph, after its
      // line-break mark, and a backspace deletes that mark.
      editing.moveToParagraph(1);
      await tester.pump();
      await tester.pump();
      final field = focusedField(tester).controller;
      expect(field.selection, const TextSelection.collapsed(offset: 1));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Q3',
          selection: TextSelection.collapsed(offset: 0),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(editing.draft!.plainText, 'Quarterly reviewQ3');
      expect(paragraphKey(1), findsNothing);
      expect(editing.textSelection, const TextSelection.collapsed(offset: 16));
    });

    testBothViewports('Delete at a paragraph end joins the next one',
        (tester, size) async {
      await pump(tester, size);
      await editTitle(tester);
      await typeText(tester, '\nQ3');
      editing.moveToParagraph(0, atEnd: true);
      await tester.pump();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(editing.draft!.plainText, 'Quarterly reviewQ3');
    });

    testBothViewports('arrows cross between paragraphs', (tester, size) async {
      await pump(tester, size);
      await editTitle(tester);
      await typeText(tester, '\nQ3');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.pump();
      expect(editing.focusedParagraph, 0);
      expect(editing.textSelection, const TextSelection.collapsed(offset: 16));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump();
      expect(editing.focusedParagraph, 1);
      expect(editing.textSelection, const TextSelection.collapsed(offset: 17));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.pump();
      expect(editing.focusedParagraph, 0);
      expect(editing.textSelection, const TextSelection.collapsed(offset: 16));
    });

    testBothViewports('a tap in another paragraph moves the caret there',
        (tester, size) async {
      await pump(tester, size);
      await editTitle(tester);
      await typeText(tester, '\nQ3');
      expect(editing.focusedParagraph, 1);
      await tester.tapAt(tester.getCenter(find.byType(EditableText).first));
      await tester.pump();
      await tester.pump();
      expect(editing.focusedParagraph, 0);
      expect(focusedField(tester).controller.text, 'Quarterly review');
      await typeText(tester, '#');
      expect(editing.draft!.paragraphs.first.plainText, contains('#'));
      expect(editing.draft!.paragraphs[1].plainText, 'Q3');
    });

    testBothViewports('Ctrl+Z steps back through the session, not the deck',
        (tester, size) async {
      await pump(tester, size);
      await editTitle(tester);
      await typeText(tester, '\nQ3');
      await typeText(tester, '!');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.pump();
      expect(editing.draft!.plainText, 'Quarterly review\nQ3');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.pump();
      expect(editing.draft!.plainText, 'Quarterly review');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(editing.draft!.plainText, 'Quarterly review\nQ3');
      expect(editing.isEditing, isTrue);
      expect(doc.controller.canUndo, isFalse);
    });

    testBothViewports('a growing box grows to its text when committed',
        (tester, size) async {
      await pump(tester, size);
      await editTitle(tester);
      for (var i = 0; i < 4; i++) {
        await typeText(tester, '\nmore');
      }
      // The selection outline follows the draft while typing.
      expect(editing.draft!.frame.height, 200);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(textBox(doc, 'title').frame.height, greaterThan(200));
      expect(undoAll(doc), 1);
    });

    testBothViewports('undoing the box away mid-session drops the session',
        (tester, size) async {
      doc.controller.addElement(
        's',
        TextBox(
          id: 'late',
          frame: ElementFrame(x: 100, y: 900, width: 400, height: 100),
        ),
      );
      await pump(tester, size);
      await tester.tapAt(slideToGlobal(tester, const Offset(300, 950)));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(editing.elementId, 'late');
      doc.controller.undo();
      await tester.pump();
      expect(editing.isEditing, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('formatting', () {
    testBothViewports('formats the selected boxes whole when not editing',
        (tester, size) async {
      await pump(tester, size);
      harness(tester).select({'title', 'box'});
      await tester.pump();
      expect(editing.canFormat, isTrue);
      expect(editing.selectionFormat.bold, isNull, reason: 'mixed');
      editing.toggle(TextToggle.bold);
      editing.format(const TextFormat(alignment: TextAlignment.end));
      await tester.pump();
      final title = textBox(doc, 'title');
      expect(title.paragraphs.single.runs.single.bold, isTrue);
      expect(title.paragraphs.single.alignment, TextAlignment.end);
      expect(editing.selectionFormat.bold, isTrue);
      expect(undoAll(doc), 2);
    });

    testBothViewports('nothing to format without a text box',
        (tester, size) async {
      await pump(tester, size);
      harness(tester).select({'box'});
      await tester.pump();
      expect(editing.canFormat, isFalse);
      editing.toggle(TextToggle.bold);
      expect(doc.controller.canUndo, isFalse);
      expect(editing.selectionFormat, const TextFormat());
    });

    testBothViewports('formats the selected text while editing',
        (tester, size) async {
      await pump(tester, size);
      await editTitle(tester);
      // Select "Quarterly" in the field, as a drag would.
      focusedField(tester).controller.selection =
          const TextSelection(baseOffset: 0, extentOffset: 9);
      await tester.pump();
      expect(editing.textSelection.textInside(editing.draft!.plainText),
          'Quarterly');
      expect(editing.selectionFormat.bold, isFalse);
      editing.format(const TextFormat(
        underline: true,
        fontFamily: 'Inter',
        color: SlideColor.white,
      ));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(textBox(doc, 'title').paragraphs.single.runs, const [
        TextRun(
          'Quarterly',
          underline: true,
          fontSize: 72,
          fontFamily: 'Inter',
          color: SlideColor.white,
        ),
        TextRun(' ', fontSize: 72),
        TextRun('review', bold: true, fontSize: 72),
      ]);
      expect(undoAll(doc), 1);
    });

    testBothViewports('Ctrl+A then Ctrl+B bolds every paragraph',
        (tester, size) async {
      await pump(tester, size);
      await editTitle(tester);
      await typeText(tester, '\nQ3');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      final runs = editing.draft!.paragraphs.expand((p) => p.runs);
      expect(runs.every((r) => r.bold), isTrue);
      expect(TextToggle.bold.isOn(editing.selectionFormat), isTrue);
    });

    testBothViewports('a format at a collapsed caret styles what comes next',
        (tester, size) async {
      await pump(tester, size);
      await editTitle(tester);
      editing.format(const TextFormat(fontSize: 20.0));
      await tester.pump();
      expect(editing.selectionFormat.fontSize, 20);
      await typeText(tester, 'x');
      expect(
        editing.draft!.paragraphs.single.runs.last,
        const TextRun('x', bold: true, fontSize: 20),
      );
    });

    testBothViewports('lists draw markers and box fields apply',
        (tester, size) async {
      await pump(tester, size);
      await editTitle(tester);
      await typeText(tester, '\nQ3');
      editing.selectAll();
      editing.toggle(TextToggle.numberedList);
      editing.format(const TextFormat(
        anchor: TextAnchor.bottom,
        lineSpacing: 1.5,
      ));
      await tester.pump();
      expect(find.text('1.', findRichText: true), findsOne);
      expect(find.text('2.', findRichText: true), findsOne);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      final title = textBox(doc, 'title');
      expect(title.anchor, TextAnchor.bottom);
      expect(title.paragraphs.map((p) => p.list),
          everyElement(TextListStyle.numbered));
      expect(title.paragraphs.map((p) => p.lineSpacing), everyElement(1.5));
      expect(find.text('2.', findRichText: true), findsOne);
      expect(undoAll(doc), 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('the text tool', () {
    testBothViewports('a click places a box ready for typing',
        (tester, size) async {
      await pump(tester, size);
      harness(tester).useTool(SlideCanvasTool.text);
      await tester.pump();
      await tester.tapAt(slideToGlobal(tester, const Offset(200, 900)));
      await tester.pump();
      await tester.pump();
      expect(harness(tester).tool, SlideCanvasTool.select);
      expect(harness(tester).selection, {'new'});
      expect(editing.elementId, 'new');
      final box = textBox(doc, 'new');
      expect(box.frame.x, closeTo(200, 1));
      expect(box.frame.width, SlideDocumentController.defaultTextBoxWidth);
      await typeText(tester, 'Hello');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(textBox(doc, 'new').plainText, 'Hello');
      expect(undoAll(doc), 2, reason: 'inserting, then typing');
    });

    testBothViewports('a drag draws the box', (tester, size) async {
      await pump(tester, size);
      harness(tester).useTool(SlideCanvasTool.text);
      await tester.pump();
      final from = slideToGlobal(tester, const Offset(100, 600));
      final to = slideToGlobal(tester, const Offset(900, 1000));
      final gesture = await tester.startGesture(from);
      await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
      await gesture.moveTo(to);
      await gesture.up();
      await tester.pump();
      final box = textBox(doc, 'new');
      expect(box.frame.width, closeTo(800, 2));
      expect(box.frame.height, closeTo(400, 2));
    });

    testBothViewports('a new box left empty disappears again',
        (tester, size) async {
      await pump(tester, size);
      harness(tester).useTool(SlideCanvasTool.text);
      await tester.pump();
      await tester.tapAt(slideToGlobal(tester, const Offset(200, 900)));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(doc.presentation, canvasDeck());
      expect(doc.controller.canUndo, isFalse);
    });
  });

  group('accessibility', () {
    testBothViewports('editing announces itself and the field reads its text',
        (tester, size) async {
      final semantics = tester.ensureSemantics();
      final announcements = <String>[];
      tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler(
        SystemChannels.accessibility,
        (message) async {
          final data = (message as Map)['data'] as Map;
          if (data['message'] != null) announcements.add('${data['message']}');
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler(SystemChannels.accessibility, null));
      await pump(tester, size);
      expect(find.bySemanticsLabel('Quarterly review'), findsOne);
      await editTitle(tester);
      expect(announcements, ['Editing text']);
      expect(
        find.semantics.byValue('Quarterly review'),
        findsOne,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(announcements, ['Editing text', 'Done editing text']);
      semantics.dispose();
    });

    testBothViewports('a screen reader tap on a selected text box edits it',
        (tester, size) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, size);
      final title = find.semantics.byLabel('Quarterly review');
      tester.semantics.tap(title);
      await tester.pump();
      expect(harness(tester).selection, {'title'});
      expect(editing.isEditing, isFalse);
      tester.semantics.tap(title);
      await tester.pump();
      expect(editing.elementId, 'title');
      semantics.dispose();
    });

    testBothViewports('200% text scale leaves the editor alone',
        (tester, size) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester, size);
      final before = tester.getRect(
        find.descendant(
          of: elementKey('title'),
          matching: find.byType(RichText),
        ),
      );
      await editTitle(tester);
      await typeText(tester, '\nmore');
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byType(EditableText).first).height,
          closeTo(before.height, 0.01));
    });

    testBothViewports('an empty box shows its placeholder only while editable',
        (tester, size) async {
      doc.controller.addElement(
        's',
        TextBox(
          id: 'sub',
          frame: ElementFrame(x: 100, y: 900, width: 800, height: 100),
          placeholder: 'Click to add subtitle',
        ),
      );
      await pump(tester, size);
      expect(find.text('Click to add subtitle', findRichText: true), findsOne);
      await tester.pumpWidget(
        MaterialApp(
          home: SlideCanvas.readOnly(
            slide: doc.presentation.slides.single,
            size: doc.presentation.size,
          ),
        ),
      );
      expect(
        find.text('Click to add subtitle', findRichText: true),
        findsNothing,
      );
    });
  });
}
