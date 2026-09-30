import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Presses Tab until keyboard focus lands inside [target], the way a keyboard
/// user reaches it, and fails when it never does.
Future<void> tabTo(
  WidgetTester tester,
  Finder target, {
  int maxTabs = 30,
}) async {
  for (var i = 0; i < maxTabs; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus?.context;
    final inside = find.descendant(
      of: target,
      matching: find.byElementPredicate((element) => element == focused),
    );
    if (focused != null && inside.evaluate().isNotEmpty) return;
  }
  fail('Tab never reached $target');
}

/// Presses Shift+F10, the context-menu shortcut on a keyboard without a menu
/// key.
Future<void> pressShiftF10(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.f10);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
}
