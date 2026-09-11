import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/document_editor/document_page_frame.dart';

// A caret is the standard "this field is focused, type here" signal, so the
// page must not draw one while it is read-only: the editor is not focused in
// that state, the blink timer never starts, and the static caret reads as
// "ready to type" when keystrokes go nowhere (#1853).
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
