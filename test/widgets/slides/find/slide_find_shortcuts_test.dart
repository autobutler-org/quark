import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/find/slide_find_shortcuts.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' as tap;

/// Ctrl or Cmd F finds and H replaces, from anywhere in the editor — a text
/// field included — and other chords pass through (#1176).
void main() {
  late List<String> events;

  setUp(() => events = []);

  Future<void> pumpShortcuts(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: Scaffold(
          body: SlideFindShortcuts(
            onFind: () => events.add('find'),
            onReplace: () => events.add('replace'),
            child: Column(
              children: [
                Focus(
                  key: const ValueKey('target'),
                  autofocus: true,
                  child: const SizedBox(width: 100, height: 100),
                ),
                const SizedBox(
                  width: 200,
                  child: TextField(key: ValueKey('notes')),
                ),
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
    testWidgets('Ctrl and Cmd F and H ($name)', (tester) async {
      tap.setViewport(tester, size);
      await pumpShortcuts(tester);
      const ctrl = LogicalKeyboardKey.controlLeft;
      const meta = LogicalKeyboardKey.metaLeft;
      await chord(tester, [ctrl], LogicalKeyboardKey.keyF);
      await chord(tester, [meta], LogicalKeyboardKey.keyF);
      await chord(tester, [ctrl], LogicalKeyboardKey.keyH);
      await chord(tester, [meta], LogicalKeyboardKey.keyH);
      expect(events, ['find', 'find', 'replace', 'replace']);
    });

    testWidgets('other chords pass through ($name)', (tester) async {
      tap.setViewport(tester, size);
      await pumpShortcuts(tester);
      await chord(tester, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ], LogicalKeyboardKey.keyF);
      await chord(tester, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.altLeft,
      ], LogicalKeyboardKey.keyF);
      await chord(tester, [
        LogicalKeyboardKey.controlLeft,
      ], LogicalKeyboardKey.keyG);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      expect(events, isEmpty);
    });

    testWidgets('works from a text field too ($name)', (tester) async {
      tap.setViewport(tester, size);
      await pumpShortcuts(tester);
      await tester.tap(find.byKey(const ValueKey('notes')));
      await tester.pump();
      await chord(tester, [
        LogicalKeyboardKey.controlLeft,
      ], LogicalKeyboardKey.keyF);
      expect(events, ['find']);
    });
  }
}
