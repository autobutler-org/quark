// The macOS-defaults tests live in their own file, and so in their own isolate.
//
// flutter_quill builds its default shortcut map from a top-level
// `final _isDesktopMacOS = isMacOS;` (lib/src/common/utils/platform.dart), which
// is lazily initialized on FIRST access and then latched for the life of the
// isolate. Whichever editor pumps first decides whether the package binds
// Cmd+Up/Cmd+Down (macOS) or Ctrl+Up/Ctrl+Down (everything else) to its own
// `ScrollIntent` — for every later test in the same file. Quarantining the
// macOS cases here means no test added to `editor_shortcuts_test.dart` can flip
// that latch out from under them, and the Cmd+B check below fails loudly if it
// ever happens anyway.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/editor_shortcuts.dart';

void main() {
  // Every test here runs under the override, so the very first editor pump in
  // this isolate is the one that latches flutter_quill's platform.
  Future<void> onMac(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<(QuillController, FocusNode)> pumpEditor(
    WidgetTester tester, {
    required Map<ShortcutActivator, Intent> customShortcuts,
  }) async {
    final controller = QuillController.basic();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    controller.document.insert(0, 'first line\nsecond line');
    controller.updateSelection(
      const TextSelection.collapsed(offset: 11),
      ChangeSource.local,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates:
            FlutterQuillLocalizations.localizationsDelegates,
        home: Scaffold(
          body: QuillEditor.basic(
            controller: controller,
            focusNode: focus,
            config: QuillEditorConfig(customShortcuts: customShortcuts),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Stop the test text input emulating native macOS selectors, which would
    // move the caret itself and mask what the shortcut layer did.
    tester.testTextInput.reset();
    return (controller, focus);
  }

  Future<void> pressWithMeta(
    WidgetTester tester,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta, platform: 'web');
    await tester.sendKeyDownEvent(key, platform: 'web');
    await tester.sendKeyUpEvent(key, platform: 'web');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta, platform: 'web');
    await tester.pump();
  }

  final macShortcuts = editorNavigationShortcuts(
    isWeb: true,
    platform: TargetPlatform.macOS,
  );

  testWidgets(
    'flutter_quill really did build its macOS defaults here',
    (tester) => onMac(() async {
      final (controller, _) = await pumpEditor(
        tester,
        customShortcuts: const {},
      );

      // Cmd+B is bold only in the macOS map; the Ctrl/Windows map binds Ctrl+B.
      // If this fails the isolate latched the wrong platform and the tests below
      // would pass without ever meeting flutter_quill's Cmd+Up ScrollIntent.
      await pressWithMeta(tester, LogicalKeyboardKey.keyB);

      expect(controller.getSelectionStyle().attributes, contains('bold'));
    }),
  );

  testWidgets(
    'Cmd+Up beats flutter_quill ScrollIntent and reaches offset 0',
    (tester) => onMac(() async {
      final (controller, _) = await pumpEditor(
        tester,
        customShortcuts: macShortcuts,
      );

      await pressWithMeta(tester, LogicalKeyboardKey.arrowUp);

      expect(controller.selection.isCollapsed, isTrue);
      expect(controller.selection.baseOffset, 0);
    }),
  );

  testWidgets(
    'Cmd+Down beats flutter_quill ScrollIntent and reaches the end',
    (tester) => onMac(() async {
      final (controller, _) = await pumpEditor(
        tester,
        customShortcuts: macShortcuts,
      );

      await pressWithMeta(tester, LogicalKeyboardKey.arrowDown);

      expect(controller.selection.isCollapsed, isTrue);
      expect(controller.selection.baseOffset, 22);
    }),
  );

  testWidgets(
    'without our map, Cmd+Up scrolls instead of moving the caret',
    (tester) => onMac(() async {
      final (controller, _) = await pumpEditor(
        tester,
        customShortcuts: const {},
      );

      await pressWithMeta(tester, LogicalKeyboardKey.arrowUp);

      expect(controller.selection.baseOffset, 11);
    }),
  );
}
