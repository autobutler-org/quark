import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/sharing_service.dart';
import 'package:quark/utils/error_text.dart';

/// The sharing routes the share sheet calls (#1911): their shapes, and that
/// the Quark's own refusals reach the person sharing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <http.Request>[];

  /// Answers every request with [status] and [body], recording it.
  void answer(int status, Object? body) {
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

  final access = {
    'deviceSerial': 'ssd1',
    'relPath': 'Photos/Family',
    'canManage': true,
    'canGrantOwner': true,
    'grants': [
      {
        'userId': 2,
        'name': 'bob',
        'builtin': false,
        'level': 'owner',
        'from': 'Photos/Family',
      },
      {
        'groupId': 1,
        'name': 'everyone',
        'builtin': true,
        'level': 'read',
        'from': '',
      },
    ],
  };

  test('loads the access to a path', () async {
    answer(200, access);

    final result = await SharingService.load(
      deviceSerial: 'ssd1',
      relPath: 'Photos/Family/',
    );

    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/v0/access');
    expect(requests.single.url.queryParameters, {
      'serial': 'ssd1',
      'relPath': 'Photos/Family/',
    });
    expect(result.relPath, 'Photos/Family');
    expect(result.canManage, isTrue);
    expect(result.canGrantOwner, isTrue);
    final [bob, everyone] = result.grants;
    expect((bob.userId, bob.groupId, bob.level), (2, null, 'owner'));
    expect(bob.from, 'Photos/Family');
    expect((everyone.userId, everyone.groupId), (null, 1));
    expect(everyone.builtin, isTrue);
    expect(everyone.from, '');
  });

  test('grants a group access without naming an account', () async {
    answer(200, access);

    await SharingService.grant(
      deviceSerial: 'ssd1',
      relPath: 'Photos/Family',
      groupId: 2,
      level: 'write',
    );

    expect(requests.single.method, 'PUT');
    expect(requests.single.url.path, '/api/v0/access');
    expect(jsonDecode(requests.single.body), {
      'deviceSerial': 'ssd1',
      'relPath': 'Photos/Family',
      'groupId': 2,
      'level': 'write',
    });
  });

  test('revokes an account and answers with the access left', () async {
    answer(200, {...access, 'grants': <Object>[]});

    final result = await SharingService.revoke(
      deviceSerial: 'ssd1',
      relPath: 'Photos/Family',
      userId: 2,
    );

    expect(requests.single.method, 'DELETE');
    expect(jsonDecode(requests.single.body), {
      'deviceSerial': 'ssd1',
      'relPath': 'Photos/Family',
      'userId': 2,
    });
    expect(result.grants, isEmpty);
  });

  test('lists who a path can be shared with', () async {
    answer(200, {
      'users': [
        {'id': 1, 'username': 'ada'},
      ],
      'groups': [
        {'id': 1, 'name': 'everyone', 'builtin': true},
        {'id': 2, 'name': 'Family', 'builtin': false},
      ],
    });

    final result = await SharingService.principals();

    expect(requests.single.url.path, '/api/v0/access/principals');
    expect(result.users, [(id: 1, username: 'ada')]);
    expect(result.groups, [
      (id: 1, name: 'everyone', builtin: true),
      (id: 2, name: 'Family', builtin: false),
    ]);
  });

  for (final (status, text) in [
    (403, 'only the owner or an admin can change sharing'),
    (409, 'that access comes from a parent folder; change it there'),
    (400, "you can't remove your own ownership; ask another owner or an admin"),
  ]) {
    test("a $status passes the Quark's words on", () async {
      answer(status, {'error': text});

      await expectLater(
        SharingService.revoke(
          deviceSerial: 'ssd1',
          relPath: 'Photos/Family',
          userId: 2,
        ),
        throwsA(
          isA<MessageException>().having((e) => e.message, 'message', text),
        ),
      );
    });
  }
}
