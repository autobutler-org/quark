import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/slide_editor_shortcuts.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart' as tap;

/// The slide editor's undo and redo keys, with Ctrl or Cmd, wherever focus
/// is inside the editor — except in a text field, which keeps them (#1153).
void main() {
  late List<String> events;

  setUp(() => events = []);

  Future<void> pumpShortcuts(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: Scaffold(
          body: SlideEditorShortcuts(
            onUndo: () => events.add('undo'),
            onRedo: () => events.add('redo'),
            child: Column(
              children: [
                Focus(
                  key: const ValueKey('target'),
                  autofocus: true,
                  child: const SizedBox(width: 100, height: 100),
                ),
                const SizedBox(width: 200, child: TextField()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> chord(
    WidgetTester tester,
    List<LogicalKeyboardKey> modifiers,
    LogicalKeyboardKey key,
  ) async {
    for (final m in modifiers) {
      await tester.sendKeyDownEvent(m);
    }
    await tester.sendKeyEvent(key);
    for (final m in modifiers.reversed) {
      await tester.sendKeyUpEvent(m);
    }
  }

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('Ctrl and Cmd undo and redo ($name)', (tester) async {
      tap.setViewport(tester, size);
      await pumpShortcuts(tester);
      const ctrl = LogicalKeyboardKey.controlLeft;
      const cmd = LogicalKeyboardKey.metaLeft;
      const shift = LogicalKeyboardKey.shiftLeft;
      await chord(tester, [ctrl], LogicalKeyboardKey.keyZ);
      await chord(tester, [ctrl, shift], LogicalKeyboardKey.keyZ);
      await chord(tester, [cmd], LogicalKeyboardKey.keyZ);
      await chord(tester, [cmd, shift], LogicalKeyboardKey.keyZ);
      await chord(tester, [ctrl], LogicalKeyboardKey.keyY);
      // Z alone, and Cmd+Y, are not history keys.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await chord(tester, [cmd], LogicalKeyboardKey.keyY);
      expect(events, ['undo', 'redo', 'undo', 'redo', 'redo']);
    });
  }

  testWidgets('a text field keeps its own undo', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    await pumpShortcuts(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await chord(tester, [
      LogicalKeyboardKey.controlLeft,
    ], LogicalKeyboardKey.keyZ);
    expect(events, isEmpty);
  });
}
