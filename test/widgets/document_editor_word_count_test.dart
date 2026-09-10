import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/document_editor/document_editor_body.dart';

/// #1816: the word count was page state, so every recount rebuilt the editor
/// along with the status bar. It now arrives as a listenable the status bar
/// watches on its own.
void main() {
  testWidgets(
    'word count follows its listenable without a rebuild from above',
    (tester) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);
      final wordCount = ValueNotifier(0);
      addTearDown(wordCount.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates:
              FlutterQuillLocalizations.localizationsDelegates,
          home: Scaffold(
            body: DocumentEditorBody(
              loading: false,
              error: null,
              onRetry: () {},
              controller: controller,
              editorFocus: FocusNode(),
              scrollController: ScrollController(),
              isReadOnly: true,
              showFindBar: false,
              onToggleFindBar: () {},
              onPickBackgroundColor: (_, _) async {},
              darkPage: false,
              onToggleDarkPage: () {},
              onEditorTap: () {},
              onEditorKey: (_, _) => null,
              wordCount: wordCount,
              dirty: false,
            ),
          ),
        ),
      );

      expect(find.text('0 words'), findsOneWidget);

      wordCount.value = 42;
      await tester.pump();

      expect(find.text('42 words'), findsOneWidget);
    },
  );
}
