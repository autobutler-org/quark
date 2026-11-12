import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/document_editor/document_find_bar.dart';

/// The find bar renders inline, not in a dialog, so nothing inside it may pop
/// the route — flutter_quill's own close button does exactly that, which is why
/// [DocumentFindBar] supplies its own chrome (#1046).
void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required QuillController controller,
    required VoidCallback onClose,
    Widget? child,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates:
            FlutterQuillLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Column(
            children: [
              child ??
                  DocumentFindBar(controller: controller, onClose: onClose),
              const Expanded(child: Text('editor body')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('close button closes the bar without popping the route', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    var closed = 0;

    await pumpBar(tester, controller: controller, onClose: () => closed++);
    await tester.tap(find.byTooltip('Close find bar (Esc)'));
    await tester.pumpAndSettle();

    expect(closed, 1);
    // The page is still there — popping it would tear the route down.
    expect(find.text('editor body'), findsOneWidget);
  });

  testWidgets('takes focus even when something else already has it', (
    tester,
  ) async {
    final controller = QuillController.basic();
    final other = FocusNode(debugLabel: 'editor');
    addTearDown(controller.dispose);
    addTearDown(other.dispose);
    var showBar = false;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates:
            FlutterQuillLocalizations.localizationsDelegates,
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Column(
              children: [
                if (showBar)
                  DocumentFindBar(controller: controller, onClose: () {}),
                Focus(
                  focusNode: other,
                  child: TextButton(
                    onPressed: () => setState(() => showBar = true),
                    child: const Text('open find'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Stands in for the editor holding focus when Ctrl/Cmd+F is pressed — that
    // is what made the field's `autofocus` a no-op.
    other.requestFocus();
    await tester.pump();
    expect(other.hasFocus, isTrue);

    await tester.tap(find.text('open find'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
      isTrue,
    );
  });

  testWidgets('typing selects the first match and counts the hits', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    controller.document.insert(0, 'alpha beta alpha gamma alpha');

    await pumpBar(tester, controller: controller, onClose: () {});
    await tester.enterText(find.byType(TextField), 'alpha');
    // The search is debounced by 300ms inside QuillToolbarSearchDialog.
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('1/3'), findsOneWidget);
    expect(controller.selection.baseOffset, 0);

    await tester.tap(find.byTooltip('Next match'));
    await tester.pumpAndSettle();

    expect(find.text('2/3'), findsOneWidget);
    expect(controller.selection.baseOffset, 11);
  });

  testWidgets('quill\'s own chrome pops the route it is rendered in', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);

    // Guards the premise: this is the behavior DocumentFindBar replaces.
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates:
            FlutterQuillLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: Column(
                      children: [
                        SizedBox(
                          height: 60,
                          child: QuillToolbarSearchDialog(
                            controller: controller,
                          ),
                        ),
                        const Expanded(child: Text('editor body')),
                      ],
                    ),
                  ),
                ),
              ),
              child: const Text('open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open editor'));
    await tester.pumpAndSettle();
    expect(find.text('editor body'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(
      find.text('editor body'),
      findsNothing,
      reason: 'closing the search bar backed out of the editor entirely',
    );
  });
}
