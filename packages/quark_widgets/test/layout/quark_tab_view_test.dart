import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The tabs on the Users page (#1910). Worth guarding: the keys a `.probe`
/// script taps, that a tap shows that tab's content and only it, and that a
/// narrow phone survives long labels.
void main() {
  const tabs = [
    QuarkTab(label: 'Accounts', child: Text('the accounts')),
    QuarkTab(label: 'Groups', child: Text('the groups')),
  ];

  testBothViewports('shows every tab and the first one is selected', (
    tester,
    size,
  ) async {
    await pumpAt(tester, const QuarkTabView(tabs: tabs), size: size);

    expect(find.byKey(const ValueKey('tab_accounts')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab_groups')), findsOneWidget);
    expect(find.text('the accounts'), findsOneWidget);
    expect(find.text('the groups'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('shows the content of the tab that was tapped', (
    tester,
    size,
  ) async {
    await pumpAt(tester, const QuarkTabView(tabs: tabs), size: size);

    await tester.tap(find.byKey(const ValueKey('tab_groups')));
    await tester.pumpAndSettle();

    expect(find.text('the groups'), findsOneWidget);
    expect(find.text('the accounts'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tab_accounts')));
    await tester.pumpAndSettle();

    expect(find.text('the accounts'), findsOneWidget);
  });

  testWidgets('a tab key follows the section slug rule', (tester) async {
    await pumpAt(
      tester,
      const QuarkTabView(
        tabs: [
          QuarkTab(label: 'Help & Support', child: SizedBox()),
          QuarkTab(label: 'Groups', child: SizedBox()),
        ],
      ),
    );

    expect(find.byKey(const ValueKey('tab_help_support')), findsOneWidget);
  });

  testBothViewports('survives long labels and a long list in a tab', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkTabView(
        tabs: [
          QuarkTab(
            label: 'Accounts ' * 8,
            child: ListView(
              children: [for (var i = 0; i < 100; i++) Text('row $i')],
            ),
          ),
          QuarkTab(label: 'Groups ' * 8, child: const SizedBox()),
          const QuarkTab(label: 'Requests', child: SizedBox()),
        ],
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: colors come from the tokens', (tester) async {
      await pumpAt(
        tester,
        const QuarkTabView(tabs: tabs),
        brightness: brightness,
      );

      expect(tester.takeException(), isNull);
      final bar = tester.widget<TabBar>(find.byType(TabBar));
      expect(bar.labelColor, tokens.foreground);
      expect(bar.unselectedLabelColor, tokens.mutedForeground);
      expect(bar.indicatorColor, tokens.primary);
      expect(bar.dividerColor, tokens.border);
    });
  }
}
