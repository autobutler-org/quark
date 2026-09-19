import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/models/user_account.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/users_service.dart';
import 'package:quark/utils/error_text.dart';

/// The admin account routes the Users page calls (#1662, #1908), and which
/// refusals get the app's copy rather than the Quark's.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <http.Request>[];

  /// Answers every request with [status] and [body], recording it.
  void answer(int status, Object body) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode(body), status);
    });
  }

  setUp(requests.clear);
  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  test('lists every account, pending requests included', () async {
    answer(200, [
      {
        'id': 1,
        'username': 'ada',
        'isAdmin': true,
        'status': 'active',
        'createdAt': '2026-09-01T12:00:00Z',
      },
      {
        'id': 2,
        'username': 'cy',
        'isAdmin': false,
        'status': 'pending',
        'createdAt': '2026-09-02T12:00:00Z',
      },
    ]);

    final users = await UsersService.list();

    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/v0/admin/users');
    expect(users.map((u) => u.username), ['ada', 'cy']);
    expect(users.first.isAdmin, isTrue);
    expect(users.first.createdAt, DateTime.utc(2026, 9, 1, 12));
    expect(users.last.status, UserAccount.pending);
  });

  for (final (name, call, path) in [
    ('promotes', UsersService.promote, '/api/v0/admin/promote/bob.smith'),
    ('approves', UsersService.approve, '/api/v0/admin/approve/bob.smith'),
    ('denies', UsersService.deny, '/api/v0/admin/deny/bob.smith'),
  ]) {
    test('$name through the account route', () async {
      answer(200, {});

      await call('bob.smith');

      expect(requests.single.method, 'PUT');
      expect(requests.single.url.path, path);
    });
  }

  test('a 409 from demote is the last-admin sentence', () async {
    answer(409, {'error': 'this Quark needs at least one active admin'});

    await expectLater(
      UsersService.demote('ada'),
      throwsA(
        isA<MessageException>().having(
          (e) => e.message,
          'message',
          Errors.lastAdmin,
        ),
      ),
    );
    expect(requests.single.url.path, '/api/v0/admin/demote/ada');
  });

  test("a refusal the Quark explains passes the Quark's text on", () async {
    answer(404, {'error': 'no account request has that username'});

    await expectLater(
      UsersService.approve('nobody'),
      throwsA(
        isA<MessageException>().having(
          (e) => e.message,
          'message',
          'no account request has that username',
        ),
      ),
    );
  });

  test('a 403 reads as a permission failure, not the Quark text', () async {
    answer(403, {'error': 'admin access required'});

    await expectLater(
      UsersService.list(),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
    );
  });

  test(
    'saves the access-requests setting and returns what was saved',
    () async {
      answer(200, {'enabled': false});

      final saved = await UsersService.setAccessRequestsEnabled(false);

      expect(saved, isFalse);
      final request = requests.single;
      expect(request.method, 'PUT');
      expect(request.url.path, '/api/v0/settings/access-requests');
      expect(jsonDecode(request.body), {'enabled': false});
    },
  );

  test('creates an account', () async {
    answer(201, {
      'id': 5,
      'username': 'bob',
      'isAdmin': false,
      'status': 'active',
      'createdAt': '2026-09-14T12:00:00Z',
    });

    final created = await UsersService.create(
      username: 'bob',
      password: 'hunter2hunter2',
    );

    expect(created.username, 'bob');
    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/api/v0/admin/users');
    expect(jsonDecode(request.body), {
      'username': 'bob',
      'password': 'hunter2hunter2',
    });
  });

  test("a taken username passes the Quark's text on", () async {
    answer(409, {'error': 'that username is taken'});

    await expectLater(
      UsersService.create(username: 'bob', password: 'hunter2hunter2'),
      throwsA(
        isA<MessageException>().having(
          (e) => e.message,
          'message',
          'that username is taken',
        ),
      ),
    );
  });

  for (final (name, call, path) in [
    ('turns off', UsersService.disable, '/api/v0/admin/disable/bob'),
    ('turns on', UsersService.enable, '/api/v0/admin/enable/bob'),
  ]) {
    test('$name through the account route', () async {
      answer(200, {});

      await call('bob');

      expect(requests.single.method, 'PUT');
      expect(requests.single.url.path, path);
    });
  }

  test('deletes and reports how many owner rows moved', () async {
    answer(200, {'ownerRowsReassigned': 3});

    expect(await UsersService.delete('bob'), 3);
    expect(requests.single.method, 'DELETE');
    expect(requests.single.url.path, '/api/v0/admin/users/bob');
  });

  for (final (name, call) in [
    ('turning off', UsersService.disable),
    ('deleting', UsersService.delete),
  ]) {
    test('a 409 from $name is the last-admin sentence', () async {
      answer(409, {'error': 'this Quark needs at least one active admin'});

      await expectLater(
        call('ada'),
        throwsA(
          isA<MessageException>().having(
            (e) => e.message,
            'message',
            Errors.lastAdmin,
          ),
        ),
      );
    });
  }

  test("acting on your own account passes the Quark's text on", () async {
    answer(400, {'error': 'use Settings to change your own account'});

    await expectLater(
      UsersService.disable('ada'),
      throwsA(
        isA<MessageException>().having(
          (e) => e.message,
          'message',
          'use Settings to change your own account',
        ),
      ),
    );
  });

  test('reads the access-requests setting from the auth status', () async {
    answer(200, {'setup': true, 'accessRequestsEnabled': true});

    expect(await UsersService.accessRequestsEnabled(), isTrue);
    expect(requests.single.url.path, '/api/v0/auth/status');
  });
}
