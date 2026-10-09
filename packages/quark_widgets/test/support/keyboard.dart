import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Presses Tab until keyboard focus lands on [target] or inside it, the way a
/// keyboard user reaches a control (#2604).
///
/// A key event is also what switches Flutter to showing focus highlights, so
/// a focus ring drawn only for keyboard users is visible after this returns.
Future<void> tabTo(WidgetTester tester, Finder target) async {
  for (var presses = 0; presses < 30; presses++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) continue;
    final inside = find.descendant(
      of: target,
      matching: find.byElementPredicate((element) => element == focused),
    );
    if (target.evaluate().contains(focused) || inside.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Tab never reached $target');
}

/// The border of the first Material button under [finder], as it is drawn
/// right now.
BorderSide buttonSide(WidgetTester tester, Finder finder) {
  final material = tester.widget<Material>(
    find.descendant(of: finder, matching: find.byType(Material)).first,
  );
  return (material.shape! as OutlinedBorder).side;
}

/// The focus ring a `QuarkTappable` under [finder] draws while it holds
/// keyboard focus.
Finder findFocusRing(Finder finder) => find.descendant(
  of: finder,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.position == DecorationPosition.foreground &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).border != null,
  ),
);
