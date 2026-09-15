import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/widgets/sharing/show_share_sheet.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The share sheet host (#1911). Removing or demoting an owner can leave an
/// item that only admins manage, so it asks first, and sends nothing until
/// the admin confirms.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <http.Request>[];
  late int loadStatus;

  const bobOwner = {
    'userId': 2,
    'name': 'bob',
    'builtin': false,
    'level': 'owner',
    'from': 'Family',
  };
  const everyoneFromTop = {
    'groupId': 1,
    'name': 'everyone',
    'builtin': true,
    'level': 'read',
    'from': '',
  };

  Map<String, Object> access(List<Object> grants) => {
    'deviceSerial': 'ssd1',
    'relPath': 'Family',
    'canManage': true,
    'canGrantOwner': true,
    'grants': grants,
  };

  setUp(() {
    requests.clear();
    loadStatus = 200;
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/api/v0/access/principals') {
        return http.Response(
          jsonEncode({
            'users': [
              {'id': 2, 'username': 'bob'},
            ],
            'groups': [
              {'id': 1, 'name': 'everyone', 'builtin': true},
            ],
          }),
          200,
        );
      }
      if (request.method == 'GET' && loadStatus != 200) {
        return http.Response(
          jsonEncode({
            'error': 'only the owner or an admin can change sharing',
          }),
          loadStatus,
        );
      }
      final grants = switch (request.method) {
        'DELETE' => [everyoneFromTop],
        'PUT' => [
          {...bobOwner, 'level': 'write'},
          everyoneFromTop,
        ],
        _ => [bobOwner, everyoneFromTop],
      };
      return http.Response(jsonEncode(access(grants)), 200);
    });
  });

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  Future<void> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showShareSheet(
                context,
                deviceSerial: 'ssd1',
                relPath: 'Family',
                name: 'Family',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  Iterable<http.Request> changes() =>
      requests.where((r) => r.method == 'PUT' || r.method == 'DELETE');

  testWidgets('loads who has access to the item', (tester) async {
    await openSheet(tester);

    final load = requests.firstWhere((r) => r.url.path == '/api/v0/access');
    expect(load.url.queryParameters, {'serial': 'ssd1', 'relPath': 'Family'});
    expect(find.text('Share Family'), findsOneWidget);
    expect(find.byKey(const ValueKey('share_grant_user_2')), findsOneWidget);
    expect(find.text('Can view · From /'), findsOneWidget);
  });

  testWidgets('asks before removing an owner, and removes only on confirm', (
    tester,
  ) async {
    await openSheet(tester);

    await tapKey(tester, 'share_revoke_user_2');
    expect(find.text("Remove bob's access?"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('revoke_owner_cancel')));
    await tester.pumpAndSettle();
    expect(changes(), isEmpty);

    await tapKey(tester, 'share_revoke_user_2');
    await tester.tap(find.byKey(const ValueKey('revoke_owner_confirm')));
    await tester.pumpAndSettle();

    expect(jsonDecode(changes().single.body), {
      'deviceSerial': 'ssd1',
      'relPath': 'Family',
      'userId': 2,
    });
    expect(
      find.byKey(const ValueKey('share_grant_user_2')),
      findsNothing,
      reason: "the Quark's answer replaced the list",
    );
  });

  testWidgets('asks before giving an owner a lower level', (tester) async {
    await openSheet(tester);

    await tapKey(tester, 'share_level_user_2');
    await tester.tap(find.byKey(const ValueKey('share_level_user_2_write')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('demote_owner_confirm')), findsOneWidget);
    expect(changes(), isEmpty);

    await tester.tap(find.byKey(const ValueKey('demote_owner_confirm')));
    await tester.pumpAndSettle();

    expect(changes().single.method, 'PUT');
    expect(jsonDecode(changes().single.body)['level'], 'write');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('share_grant_user_2')),
        matching: find.text('Can edit'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('asks before the share form gives an owner a lower level', (
    tester,
  ) async {
    await openSheet(tester);

    Future<void> shareBobAsEditor() async {
      await tester.enterText(
        find.byKey(const ValueKey('principal_search')),
        'bob',
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'principal_option_user_2');
      await tapKey(tester, 'share_add_level_write');
      await tapKey(tester, 'share_add_submit');
    }

    await shareBobAsEditor();
    expect(find.text('Stop bob being an owner?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('demote_owner_cancel')));
    await tester.pumpAndSettle();
    expect(changes(), isEmpty);

    await shareBobAsEditor();
    await tester.tap(find.byKey(const ValueKey('demote_owner_confirm')));
    await tester.pumpAndSettle();

    expect(changes().single.method, 'PUT');
    expect(jsonDecode(changes().single.body)['level'], 'write');
  });

  testWidgets('a reader sees why they cannot manage sharing', (tester) async {
    loadStatus = 403;

    await openSheet(tester);

    expect(
      find.text('Only the owner or an admin can change sharing.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('principal_search')), findsNothing);
  });
}
