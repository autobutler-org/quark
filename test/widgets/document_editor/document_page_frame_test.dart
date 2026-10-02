import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/document_editor/document_page_frame.dart';

// The editor page, and the two things about it that have to match what a
// writer expects from any other document editor: a caret only where typing
// works (#1853), and Tab indenting the block rather than dropping a literal
// tab character into the line (#1855).
void main() {
  late QuillController controller;
  late FocusNode editorFocus;
  late ScrollController scrollController;

  setUp(() {
    controller = QuillController.basic();
    editorFocus = FocusNode();
    scrollController = ScrollController();
  });

  tearDown(() {
    controller.dispose();
    editorFocus.dispose();
    scrollController.dispose();
  });

  Future<void> pumpFrame(
    WidgetTester tester, {
    required bool isReadOnly,
    VoidCallback? onTap,
  }) async {
    controller.readOnly = isReadOnly;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [FlutterQuillLocalizations.delegate],
        home: Scaffold(
          body: DocumentPageFrame(
            controller: controller,
            editorFocus: editorFocus,
            scrollController: scrollController,
            darkPage: false,
            isReadOnly: isReadOnly,
            onTap: onTap ?? () {},
            onKeyPressed: (_, _) => null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool? shownCursor(WidgetTester tester) =>
      tester.widget<QuillEditor>(find.byType(QuillEditor)).config.showCursor;

  /// The attributes on the line the caret is on. Quill hangs block attributes
  /// off the line's newline, so `indent` shows up there.
  Map<String, dynamic> lineAttributes(QuillController controller) {
    for (final op in controller.document.toDelta().toJson()) {
      if (op['insert'] == '\n') {
        return (op['attributes'] as Map<String, dynamic>?) ?? {};
      }
    }
    return {};
  }

  testWidgets('draws no caret while the document is read-only', (
    WidgetTester tester,
  ) async {
    await pumpFrame(tester, isReadOnly: true);

    expect(shownCursor(tester), isFalse);
  });

  testWidgets('draws a caret once the document is editable', (
    WidgetTester tester,
  ) async {
    await pumpFrame(tester, isReadOnly: false);

    expect(shownCursor(tester), isTrue);
  });

  // Tab indents the block instead of dropping a literal tab character into
  // the line, which is what flutter_quill does unless asked otherwise (#1855).
  testWidgets('indents the current block on Tab', (WidgetTester tester) async {
    await pumpFrame(tester, isReadOnly: false);
    editorFocus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(lineAttributes(controller), containsPair('indent', 1));
    expect(controller.document.toPlainText(), isNot(contains('\t')));
  });

  testWidgets('unindents on Shift+Tab', (WidgetTester tester) async {
    await pumpFrame(tester, isReadOnly: false);
    editorFocus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(lineAttributes(controller), isNot(contains('indent')));
  });

  /// Puts [text] in the document as a code block and selects [selection].
  Future<void> typeCodeBlock(
    WidgetTester tester,
    String text,
    TextSelection selection,
  ) async {
    await pumpFrame(tester, isReadOnly: false);
    controller
      ..replaceText(0, 0, text, selection)
      ..formatSelection(Attribute.codeBlock);
    editorFocus.requestFocus();
    await tester.pump();
  }

  Future<void> shiftTab(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
  }

  // In a code block, Tab indents the code the way a code editor does. Indenting
  // the block instead gave its lines outline numbering (a., i., ...) in the
  // gutter, as if they were nested list items.
  testWidgets('Tab in a code block indents the text, not the block', (
    WidgetTester tester,
  ) async {
    await typeCodeBlock(
      tester,
      'code',
      const TextSelection.collapsed(offset: 0),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(lineAttributes(controller), isNot(contains('indent')));
    expect(lineAttributes(controller), containsPair('code-block', true));
    expect(controller.document.toPlainText(), '\tcode\n');
    expect(controller.selection, const TextSelection.collapsed(offset: 1));
  });

  testWidgets('Shift+Tab in a code block removes leading indentation', (
    WidgetTester tester,
  ) async {
    await typeCodeBlock(
      tester,
      '\tcode',
      const TextSelection.collapsed(offset: 3),
    );

    await shiftTab(tester);

    expect(lineAttributes(controller), isNot(contains('indent')));
    expect(controller.document.toPlainText(), 'code\n');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
  });

  testWidgets('Tab and Shift+Tab indent every selected code line', (
    WidgetTester tester,
  ) async {
    await typeCodeBlock(
      tester,
      'a\nb',
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(controller.document.toPlainText(), '\ta\n\tb\n');
    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );

    await shiftTab(tester);

    expect(controller.document.toPlainText(), 'a\nb\n');
    expect(controller.document.toDelta().toJson(), [
      {'insert': 'a'},
      {
        'insert': '\n',
        'attributes': {'code-block': true},
      },
      {'insert': 'b'},
      {
        'insert': '\n',
        'attributes': {'code-block': true},
      },
    ]);
  });

  /// The left edge of the line whose text is exactly [text].
  double lineLeft(WidgetTester tester, String text) => tester
      .getTopLeft(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == text,
        ),
      )
      .dx;

  // One nesting level moved an item right by one font size, 14px, which reads
  // as a sibling rather than a child. Each level now steps by two (#2464).
  for (final list in ['bullet', 'ordered', 'unchecked']) {
    testWidgets('a nested $list item steps 28px right per level', (
      WidgetTester tester,
    ) async {
      controller.document = Document.fromJson([
        {'insert': 'one'},
        {
          'insert': '\n',
          'attributes': {'list': list},
        },
        {'insert': 'two'},
        {
          'insert': '\n',
          'attributes': {'list': list, 'indent': 1},
        },
        {'insert': 'six'},
        {
          'insert': '\n',
          'attributes': {'list': list, 'indent': 2},
        },
      ]);
      await pumpFrame(tester, isReadOnly: true);

      final one = lineLeft(tester, 'one');
      final two = lineLeft(tester, 'two');
      final six = lineLeft(tester, 'six');

      expect(two - one, 28);
      expect(six - two, 28);
    });
  }

  testWidgets('an indented paragraph steps the same 28px per level', (
    WidgetTester tester,
  ) async {
    controller.document = Document.fromJson([
      {'insert': 'one\ntwo'},
      {
        'insert': '\n',
        'attributes': {'indent': 1},
      },
    ]);
    await pumpFrame(tester, isReadOnly: true);

    expect(lineLeft(tester, 'two') - lineLeft(tester, 'one'), 28);
  });

  testWidgets('reports a tap on the page so the caller can start editing', (
    WidgetTester tester,
  ) async {
    var taps = 0;
    await pumpFrame(tester, isReadOnly: true, onTap: () => taps++);

    await tester.tap(find.byType(QuillEditor));
    await tester.pump();

    expect(taps, 1);
  });
}
