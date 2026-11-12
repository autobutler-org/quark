import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/document_editor_page.dart';

/// flutter_quill binds Ctrl/Cmd+F to its own modal search dialog. The document
/// editor shows an inline find bar instead, so the built-in dialog must never
/// open — otherwise both appear at once (#1046).
void main() {
  // flutter_quill picks its binding from the host OS (dart:io), not from
  // defaultTargetPlatform, and key simulation needs the matching platform to
  // set modifier flags — so pin both to this machine. Restored at the end of
  // each test body; a tearDown would run too late for the binding's invariant
  // check.
  final hostPlatform = Platform.isMacOS
      ? TargetPlatform.macOS
      : TargetPlatform.linux;
  final hostModifier = Platform.isMacOS
      ? LogicalKeyboardKey.meta
      : LogicalKeyboardKey.control;

  Widget app({
    required QuillController controller,
    required FocusNode focus,
    KeyEventResult? Function(KeyEvent, Node?)? onKeyPressed,
  }) {
    return MaterialApp(
      localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
      home: Scaffold(
        body: QuillEditor.basic(
          controller: controller,
          focusNode: focus,
          config: QuillEditorConfig(
            // ignore: experimental_member_use
            onKeyPressed: onKeyPressed,
          ),
        ),
      ),
    );
  }

  Future<void> pressFind(WidgetTester tester) async {
    await tester.sendKeyDownEvent(hostModifier);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(hostModifier);
    await tester.pumpAndSettle();
  }

  final searchDialog = find.byType(QuillToolbarSearchDialog);

  testWidgets('quill opens its own dialog without the interceptor', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = hostPlatform;
    final controller = QuillController.basic();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(app(controller: controller, focus: focus));
    focus.requestFocus();
    await tester.pump();
    await pressFind(tester);

    // Guards the premise of the test below: this is the dialog we suppress.
    expect(searchDialog, findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the interceptor toggles the find bar, no quill dialog', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = hostPlatform;
    final controller = QuillController.basic();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    var toggles = 0;

    await tester.pumpWidget(
      app(
        controller: controller,
        focus: focus,
        onKeyPressed: (event, node) =>
            quillFindKeyInterceptor(event, () => toggles++),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await pressFind(tester);

    expect(searchDialog, findsNothing);
    expect(toggles, 1, reason: 'key-up must not toggle a second time');
    debugDefaultTargetPlatformOverride = null;
  });

  test('plain F is left to the editor', () {
    var toggles = 0;
    final result = quillFindKeyInterceptor(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyF,
        logicalKey: LogicalKeyboardKey.keyF,
        timeStamp: Duration.zero,
      ),
      () => toggles++,
    );

    expect(result, isNull);
    expect(toggles, 0);
  });
}
