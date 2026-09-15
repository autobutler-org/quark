import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/users_page.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Users page in two tabs (#1910): the accounts, and the groups.
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
}
