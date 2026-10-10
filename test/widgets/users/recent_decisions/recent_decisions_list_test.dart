import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/account_request_decision.dart';
import 'package:quark/widgets/users/recent_decisions/recent_decisions_list.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Recent decisions list on the Users page (#2730): loading, the error,
/// the empty list and the rows, on a phone and a desktop.
void main() {
  const narrow = Size(360, 640);
  const wide = Size(1280, 800);

  AccountRequestDecision decision(
    String username, {
    bool approved = true,
    String decidedBy = 'ada',
    Duration ago = const Duration(hours: 3),
  }) => AccountRequestDecision(
    username: username,
    approved: approved,
    decidedBy: decidedBy,
    decidedAt: DateTime.now().subtract(ago),
  );

  /// Pumps [list] at [size] in a scroll view, as the page holds it.
  Future<void> pumpAt(WidgetTester tester, Size size, Widget list) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: Scaffold(
          body: ListView(padding: const EdgeInsets.all(16), children: [list]),
        ),
      ),
    );
    await tester.pump();
  }

  for (final (name, size) in [('narrow', narrow), ('wide', wide)]) {
    testWidgets('$name: shows who was approved or denied, by whom and when', (
      tester,
    ) async {
      await pumpAt(
        tester,
        size,
        RecentDecisionsList(
          decisions: [
            decision('grace'),
            decision('eli', approved: false, ago: const Duration(days: 2)),
          ],
        ),
      );

      expect(find.byKey(const ValueKey('decision_row_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('decision_row_1')), findsOneWidget);
      expect(find.text('grace'), findsOneWidget);
      expect(find.text('Approved by ada · 3h ago'), findsOneWidget);
      expect(find.text('eli'), findsOneWidget);
      expect(find.text('Denied by ada · 2d ago'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('grace')).dy,
        lessThan(tester.getTopLeft(find.text('eli')).dy),
        reason: 'the order given is the order shown',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name: long usernames are cut short, not overflowed', (
      tester,
    ) async {
      final long = 'a' * 200;
      await pumpAt(
        tester,
        size,
        RecentDecisionsList(decisions: [decision(long, decidedBy: long)]),
      );

      expect(find.byKey(const ValueKey('decision_row_0')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('decision_row_0'))).width,
        lessThanOrEqualTo(size.width),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name: loading shows a loader in place of the rows', (
      tester,
    ) async {
      await pumpAt(
        tester,
        size,
        RecentDecisionsList(decisions: [decision('grace')], isLoading: true),
      );

      expect(find.byType(QuarkLoader), findsOneWidget);
      expect(find.byKey(const ValueKey('decision_row_0')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name: the error shows in place of the rows', (tester) async {
      await pumpAt(
        tester,
        size,
        RecentDecisionsList(
          decisions: [decision('grace')],
          error: "Couldn't load recent decisions. Try again.",
        ),
      );

      expect(
        find.text("Couldn't load recent decisions. Try again."),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('decision_row_0')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name: no decisions says so', (tester) async {
      await pumpAt(tester, size, const RecentDecisionsList(decisions: []));

      expect(find.text('No decisions yet'), findsOneWidget);
      expect(find.byType(QuarkLoader), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
