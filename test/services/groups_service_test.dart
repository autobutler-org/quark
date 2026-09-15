import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/groups_service.dart';
import 'package:quark/utils/error_text.dart';

/// The admin group routes the Groups tab calls (#1910), and which refusals
/// get the app's copy rather than the Quark's.
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

  Matcher throwsMessage(String message) => throwsA(
    isA<MessageException>().having((e) => e.message, 'message', message),
  );

  test('lists the groups with their members', () async {
    answer(200, [
      {'id': 1, 'name': 'everyone', 'builtin': true, 'members': []},
      {
        'id': 2,
        'name': 'Family',
        'builtin': false,
        'members': [
          {'id': 5, 'username': 'bob'},
        ],
      },
    ]);

    final groups = await GroupsService.list();

    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/v0/admin/groups');
    expect(groups.map((g) => g.name), ['everyone', 'Family']);
    expect(groups.first.builtin, isTrue);
    expect(groups.first.members, isEmpty);
    expect(groups.last.members.single.id, 5);
    expect(groups.last.members.single.username, 'bob');
  });

  test('creates a group by name', () async {
    answer(201, {'id': 3, 'name': 'Family', 'builtin': false, 'members': []});

    await GroupsService.create('Family');

    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/v0/admin/groups');
    expect(jsonDecode(requests.single.body), {'name': 'Family'});
  });

  test('renames a group by id', () async {
    answer(200, {'id': 2, 'name': 'Kin', 'builtin': false, 'members': []});

    await GroupsService.rename(2, 'Kin');

    expect(requests.single.method, 'PUT');
    expect(requests.single.url.path, '/api/v0/admin/groups/2');
    expect(jsonDecode(requests.single.body), {'name': 'Kin'});
  });

  test('deletes a group by id', () async {
    answer(204, null);

    await GroupsService.delete(2);

    expect(requests.single.method, 'DELETE');
    expect(requests.single.url.path, '/api/v0/admin/groups/2');
  });

  test('adds and removes a member by id', () async {
    answer(204, null);

    await GroupsService.addMember(2, 5);
    await GroupsService.removeMember(2, 5);

    expect(requests.map((r) => r.method), ['PUT', 'DELETE']);
    expect(requests.map((r) => r.url.path).toSet(), {
      '/api/v0/admin/groups/2/members/5',
    });
  });

  test("a taken name passes the Quark's text on", () async {
    answer(409, {'error': 'a group with that name already exists'});

    await expectLater(
      GroupsService.create('family'),
      throwsMessage('a group with that name already exists'),
    );
  });

  test("an account that can't join gets the app's own copy", () async {
    answer(404, {'error': 'no account has that username'});

    await expectLater(
      GroupsService.addMember(2, 9),
      throwsMessage(Errors.cannotJoinGroup),
    );
  });

  test("a missing group keeps the Quark's text", () async {
    answer(404, {'error': 'no group has that id'});

    await expectLater(
      GroupsService.addMember(9, 5),
      throwsMessage('no group has that id'),
    );
  });

  test('403 reads as a permission failure', () async {
    answer(403, {'error': 'admin only'});

    await expectLater(
      GroupsService.list(),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
    );
  });
}
