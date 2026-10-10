import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/users_page.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/text_scale.dart';

/// The Users page in two tabs (#1910): the accounts with the recent decisions
/// on their requests (#2730), and the groups.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      final Object? body = switch (request.url.path) {
        '/api/v0/admin/users' => [
          {'id': 1, 'username': 'ada', 'isAdmin': true, 'status': 'active'},
        ],
        '/api/v0/auth/status' => {'setup': true, 'accessRequestsEnabled': true},
        '/api/v0/admin/groups' => [
          {'id': 1, 'name': 'everyone', 'builtin': true, 'members': []},
          {
            'id': 2,
            'name': 'Family',
            'builtin': false,
            'members': [
              {'id': 1, 'username': 'ada'},
            ],
          },
        ],
        '/api/v0/admin/account-requests/history' => [
          {
            'username': 'eli',
            'outcome': 'denied',
            'decidedBy': 'ada',
            'decidedAt': DateTime.now().toUtc().toIso8601String(),
          },
        ],
        _ => null,
      };
      return body == null
          ? http.Response('', 404)
          : http.Response(jsonEncode(body), 200);
    });
  });

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  testWidgets('opens on the accounts, with the groups on their own tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: const UsersPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tab_accounts')), findsOneWidget);
    expect(find.byKey(const ValueKey('user_row_ada')), findsOneWidget);
    expect(find.byKey(const ValueKey('group_row_1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tab_groups')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('group_row_1')), findsOneWidget);
    expect(find.text('Every account'), findsOneWidget);
    expect(find.byKey(const ValueKey('group_row_2')), findsOneWidget);
    expect(find.text('1 member'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Disposing the page stops its refresh timer.
    await tester.pumpWidget(const SizedBox());
  });
  // #2730: who was let in or turned away, by whom and when.
  testWidgets('lists the recent decisions under the accounts', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: const UsersPage(),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('decision_row_0'));
    await tester.ensureVisible(row);
    expect(find.text('Recent decisions'), findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('eli')),
      findsOneWidget,
    );
    expect(find.text('Denied by ada · just now'), findsOneWidget);
    expect(
      tester.getTopLeft(row).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const ValueKey('user_row_ada'))).dy,
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  // #2482: an approved or denied request leaves the list, so the page says
  // what happened to it. #2730: and the decision joins the recent ones
  // without waiting for the Quark's event.
  for (final (action, said, outcome, recorded) in [
    (
      'approve',
      'Approved grace. They can sign in now.',
      'approved',
      'Approved by ada · just now',
    ),
    ('deny', "Denied grace's request.", 'denied', 'Denied by ada · just now'),
  ]) {
    testWidgets('says what $action did to the request', (tester) async {
      var decided = false;
      sharedHttpClientFactory = () => MockClient((request) async {
        final path = request.url.path;
        if (path == '/api/v0/admin/$action/grace') {
          decided = true;
          return http.Response('{}', 200);
        }
        final Object? body = switch (path) {
          '/api/v0/admin/users' => [
            {'id': 1, 'username': 'ada', 'isAdmin': true, 'status': 'active'},
            if (!decided)
              {
                'id': 2,
                'username': 'grace',
                'isAdmin': false,
                'status': 'pending',
              },
          ],
          '/api/v0/auth/status' => {
            'setup': true,
            'accessRequestsEnabled': true,
          },
          '/api/v0/admin/groups' => <Object>[],
          '/api/v0/admin/account-requests/history' => [
            if (decided)
              {
                'username': 'grace',
                'outcome': outcome,
                'decidedBy': 'ada',
                'decidedAt': DateTime.now().toUtc().toIso8601String(),
              },
          ],
          _ => null,
        };
        return body == null
            ? http.Response('', 404)
            : http.Response(jsonEncode(body), 200);
      });
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
          home: const UsersPage(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No decisions yet'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('request_${action}_grace')));
      await tester.pumpAndSettle();

      expect(decided, isTrue);
      expect(find.byKey(const ValueKey('request_row_grace')), findsNothing);
      expect(find.text(said), findsOneWidget);
      expect(find.text('No decisions yet'), findsNothing);
      expect(find.text(recorded), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  }

  // #2606, #2603, #2605: both tabs survive 200% text on a phone and a
  // desktop, and every control on them is labeled and big enough to hit.
  for (final tab in ['accounts', 'groups']) {
    testLargeText('the $tab tab lays out', (tester, _) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
          home: const UsersPage(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('tab_$tab')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await expectTapTargetGuidelines(tester);

      await tester.pumpWidget(const SizedBox());
    });
  }
}
