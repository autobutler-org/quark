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
