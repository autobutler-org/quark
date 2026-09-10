import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/editor_shortcuts.dart';

void main() {
  group('editorNavigationShortcuts', () {
    test('is empty off the web, where the defaults already work', () {
      expect(
        editorNavigationShortcuts(isWeb: false, platform: TargetPlatform.macOS),
        isEmpty,
      );
      expect(
        editorNavigationShortcuts(isWeb: false, platform: TargetPlatform.linux),
        isEmpty,
      );
    });

    test('binds the Mac navigation combinations on the web', () {
      final map = editorNavigationShortcuts(
        isWeb: true,
        platform: TargetPlatform.macOS,
      );

      expect(
        map[const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true)],
        isA<ExtendSelectionToLineBreakIntent>()
            .having((i) => i.forward, 'forward', isFalse)
            .having((i) => i.collapseSelection, 'collapse', isTrue),
      );
      expect(
        map[const SingleActivator(LogicalKeyboardKey.arrowDown, meta: true)],
        isA<ExtendSelectionToDocumentBoundaryIntent>().having(
          (i) => i.forward,
          'forward',
          isTrue,
        ),
      );
      expect(
        map[const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          meta: true,
          shift: true,
        )],
        isA<ExpandSelectionToLineBreakIntent>(),
      );
      expect(
        map[const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true)],
        isA<ExtendSelectionToNextWordBoundaryIntent>().having(
          (i) => i.forward,
          'forward',
          isFalse,
        ),
      );
      expect(
        map[const SingleActivator(LogicalKeyboardKey.backspace, meta: true)],
        isA<DeleteToLineBreakIntent>(),
      );
      expect(
        map[const SingleActivator(LogicalKeyboardKey.backspace, alt: true)],
        isA<DeleteToNextWordBoundaryIntent>(),
      );
      expect(
        map[const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true)],
        isNull,
        reason: 'Ctrl+arrow is not a Mac navigation key',
      );
    });

    test('binds the Ctrl and Alt combinations elsewhere on the web', () {
      for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
        final map = editorNavigationShortcuts(isWeb: true, platform: platform);

        expect(
          map[const SingleActivator(
            LogicalKeyboardKey.arrowRight,
            control: true,
          )],
          isA<ExtendSelectionToNextWordBoundaryIntent>().having(
            (i) => i.forward,
            'forward',
            isTrue,
          ),
          reason: '$platform',
        );
        expect(
          map[const SingleActivator(LogicalKeyboardKey.home, control: true)],
          isA<ExtendSelectionToDocumentBoundaryIntent>(),
          reason: '$platform',
        );
        expect(
          map[const SingleActivator(
            LogicalKeyboardKey.backspace,
            control: true,
          )],
          isA<DeleteToNextWordBoundaryIntent>(),
          reason: '$platform',
        );
        expect(
          map[const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true)],
          isNull,
          reason: 'Cmd+arrow is not a $platform navigation key',
        );
      }
    });

    test('never rebinds a plain key or a clipboard combination', () {
      for (final platform in TargetPlatform.values) {
        final map = editorNavigationShortcuts(isWeb: true, platform: platform);
        for (final entry in map.entries) {
          final activator = entry.key as SingleActivator;
          expect(
            activator.control ||
                activator.alt ||
                activator.meta ||
                activator.trigger == LogicalKeyboardKey.home ||
                activator.trigger == LogicalKeyboardKey.end,
            isTrue,
            reason: '$platform: ${activator.debugDescribeKeys()} is unmodified',
          );
          expect(
            activator.trigger,
            isNot(
              isIn([
                LogicalKeyboardKey.keyA,
                LogicalKeyboardKey.keyC,
                LogicalKeyboardKey.keyV,
                LogicalKeyboardKey.keyX,
                LogicalKeyboardKey.keyZ,
              ]),
            ),
          );
        }
      }
    });
  });

  // flutter_quill's macOS defaults (Cmd+Up/Cmd+Down -> ScrollIntent) are
  // exercised by the sibling editor_shortcuts_macos_test.dart.
  group('in the editor', () {
    void stopNativeMacSelectorEmulation(WidgetTester tester) =>
        tester.testTextInput.reset();

    Widget app({
      required QuillController controller,
      required FocusNode focus,
      required Map<ShortcutActivator, Intent> customShortcuts,
    }) {
      return MaterialApp(
        localizationsDelegates:
            FlutterQuillLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true):
                  DoNothingAndStopPropagationTextIntent(),
              SingleActivator(LogicalKeyboardKey.arrowUp, meta: true):
                  DoNothingAndStopPropagationTextIntent(),
            },
            child: QuillEditor.basic(
              controller: controller,
              focusNode: focus,
              config: QuillEditorConfig(customShortcuts: customShortcuts),
            ),
          ),
        ),
      );
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
        const TextSelection.collapsed(offset: 22),
        ChangeSource.local,
      );

      await tester.pumpWidget(
        app(
          controller: controller,
          focus: focus,
          customShortcuts: customShortcuts,
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      stopNativeMacSelectorEmulation(tester);
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

    Future<void> onMac(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets(
      'Cmd+arrow goes nowhere once the outer map swallows it',
      (tester) => onMac(() async {
        final (controller, _) = await pumpEditor(
          tester,
          customShortcuts: const {},
        );

        await pressWithMeta(tester, LogicalKeyboardKey.arrowLeft);

        expect(
          controller.selection.baseOffset,
          22,
          reason: 'this is the web behavior the fix exists for',
        );
      }),
    );

    testWidgets(
      'Cmd+Left reaches the line start with the bindings in place',
      (tester) => onMac(() async {
        final (controller, _) = await pumpEditor(
          tester,
          customShortcuts: editorNavigationShortcuts(
            isWeb: true,
            platform: TargetPlatform.macOS,
          ),
        );

        await pressWithMeta(tester, LogicalKeyboardKey.arrowLeft);

        expect(controller.selection.isCollapsed, isTrue);
        expect(controller.selection.baseOffset, 11);
      }),
    );

    testWidgets(
      'Cmd+Up reaches the start of the document',
      (tester) => onMac(() async {
        final (controller, _) = await pumpEditor(
          tester,
          customShortcuts: editorNavigationShortcuts(
            isWeb: true,
            platform: TargetPlatform.macOS,
          ),
        );

        await pressWithMeta(tester, LogicalKeyboardKey.arrowUp);

        expect(controller.selection.isCollapsed, isTrue);
        expect(controller.selection.baseOffset, 0);
      }),
    );
  });
}
