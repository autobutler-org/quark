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

  group('controlled (#2349)', () {
    /// A caller holding the selected tab the way a routed page does: it
    /// passes [selected] in and takes every reported change.
    Widget controlled(int selected, List<int> reported) => QuarkTabView(
      selectedIndex: selected,
      onTabSelected: reported.add,
      tabs: tabs,
    );

    testBothViewports('starts on the tab it is given', (tester, size) async {
      await pumpAt(tester, controlled(1, []), size: size);

      expect(find.text('the groups'), findsOneWidget);
      expect(find.text('the accounts'), findsNothing);
    });

    testBothViewports('reports a tapped tab once', (tester, size) async {
      final reported = <int>[];
      await pumpAt(tester, controlled(0, reported), size: size);

      await tester.tap(find.byKey(const ValueKey('tab_groups')));
      await tester.pumpAndSettle();

      expect(reported, [1]);
    });

    testBothViewports('reports a swipe to another tab', (tester, size) async {
      final reported = <int>[];
      await pumpAt(tester, controlled(0, reported), size: size);

      await tester.fling(
        find.text('the accounts'),
        Offset(-size.width / 2, 0),
        1000,
      );
      await tester.pumpAndSettle();

      expect(reported, [1]);
      expect(find.text('the groups'), findsOneWidget);
    });

    testBothViewports('moves to a new selectedIndex without calling back', (
      tester,
      size,
    ) async {
      final reported = <int>[];
      await pumpAt(tester, controlled(0, reported), size: size);

      await pumpAt(tester, controlled(1, reported), size: size);
      await tester.pumpAndSettle();

      expect(find.text('the groups'), findsOneWidget);
      expect(find.text('the accounts'), findsNothing);
      expect(reported, isEmpty);
    });
  });

  group('reduced motion', () {
    /// The controller has no duration to animate over, so the indicator and
    /// the content switch in the frame just pumped.
    void expectNoSlide(WidgetTester tester) {
      final bar = tester.widget<TabBar>(find.byType(TabBar));
      expect(bar.controller!.animationDuration, Duration.zero);
    }

    Widget noAnimations(Widget child) => MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: child,
    );

    testBothViewports('a tap switches tabs without animating', (
      tester,
      size,
    ) async {
      final reported = <int>[];
      await pumpAt(
        tester,
        noAnimations(
          QuarkTabView(
            selectedIndex: 0,
            onTabSelected: reported.add,
            tabs: tabs,
          ),
        ),
        size: size,
      );

      await tester.tap(find.byKey(const ValueKey('tab_groups')));
      await tester.pump();

      expectNoSlide(tester);
      expect(find.text('the groups'), findsOneWidget);
      expect(find.text('the accounts'), findsNothing);
      expect(reported, [1]);
    });

    testBothViewports('a new selectedIndex switches without animating', (
      tester,
      size,
    ) async {
      final reported = <int>[];
      Widget at(int selected) => noAnimations(
        QuarkTabView(
          selectedIndex: selected,
          onTabSelected: reported.add,
          tabs: tabs,
        ),
      );
      await pumpAt(tester, at(0), size: size);

      await pumpAt(tester, at(1), size: size);

      expectNoSlide(tester);
      expect(find.text('the groups'), findsOneWidget);
      expect(reported, isEmpty);
    });

    testBothViewports('honors the platform reduce motion flag', (
      tester,
      size,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpAt(tester, const QuarkTabView(tabs: tabs), size: size);

      await tester.tap(find.byKey(const ValueKey('tab_groups')));
      await tester.pump();

      expectNoSlide(tester);
      expect(find.text('the groups'), findsOneWidget);
      expect(find.text('the accounts'), findsNothing);
    });

    // The control for the cases above: with motion on, one frame after a tap
    // the old tab is still sliding out.
    testWidgets('slides when motion is on', (tester) async {
      await pumpAt(tester, const QuarkTabView(tabs: tabs));

      await tester.tap(find.byKey(const ValueKey('tab_groups')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('the accounts'), findsOneWidget);
      expect(find.text('the groups'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('keeps the tab when the setting changes', (tester) async {
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final reported = <int>[];
      await pumpAt(
        tester,
        QuarkTabView(selectedIndex: 1, onTabSelected: reported.add, tabs: tabs),
      );

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      await tester.pump();

      expect(find.text('the groups'), findsOneWidget);
      expect(reported, isEmpty);

      await tester.tap(find.byKey(const ValueKey('tab_accounts')));
      await tester.pump();

      expectNoSlide(tester);
      expect(find.text('the accounts'), findsOneWidget);
      expect(find.text('the groups'), findsNothing);
      expect(reported, [0]);
      expect(tester.takeException(), isNull);
    });
  });

  group('five tabs', () {
    const five = [
      QuarkTab(label: 'General', child: Text('general')),
      QuarkTab(label: 'Account', child: Text('account')),
      QuarkTab(label: 'Storage', child: Text('storage')),
      QuarkTab(label: 'Notifications', child: Text('notifications')),
      QuarkTab(label: 'About', child: Text('about')),
    ];

    testBothViewports('fit without overflow, scrolling only when narrow', (
      tester,
      size,
    ) async {
      await pumpAt(tester, const QuarkTabView(tabs: five), size: size);

      expect(tester.takeException(), isNull);
      final bar = tester.widget<TabBar>(find.byType(TabBar));
      expect(bar.isScrollable, size == narrowViewport);
    });

    testWidgets('the last tab is reachable on a phone', (tester) async {
      await pumpAt(
        tester,
        const QuarkTabView(tabs: five),
        size: narrowViewport,
      );

      await tester.ensureVisible(find.byKey(const ValueKey('tab_about')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab_about')));
      await tester.pumpAndSettle();

      expect(find.text('about'), findsOneWidget);
    });
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
