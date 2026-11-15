import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// #4150: the phone bar's one app-wide control.
void main() {
  Finder dot() => find.descendant(
    of: find.byKey(const ValueKey('account_button')),
    matching: find.byType(Badge),
  );

  testBothViewports('shows no dot when nothing wants a look', (
    tester,
    size,
  ) async {
    await pumpAt(tester, QuarkAccountButton(onPressed: () {}), size: size);
    expect(tester.takeException(), isNull);
    expect(dot(), findsNothing);
    expect(find.byTooltip('Account'), findsOneWidget);
  });

  testBothViewports('shows a dot and says so when something does', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkAccountButton(showDot: true, onPressed: () {}),
      size: size,
    );
    expect(tester.takeException(), isNull);
    expect(dot(), findsOneWidget);
    expect(find.byTooltip('Account, something new'), findsOneWidget);
  });

  testWidgets('calls onPressed when tapped', (tester) async {
    var taps = 0;
    await pumpAt(tester, QuarkAccountButton(onPressed: () => taps++));
    await tester.tap(find.byKey(const ValueKey('account_button')));
    expect(taps, 1);
  });
}
