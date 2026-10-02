import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/sessions_service.dart';
import 'package:quark/utils/error_text.dart';

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

  test('reads the sessions and which one is current', () async {
    answer(200, {
      'sessions': [
        {
          'id': 'abc',
          'createdAt': '2026-09-01T10:00:00Z',
          'expiresAt': '2026-10-01T10:00:00Z',
          'lastUsedAt': '2026-09-02T11:30:00Z',
          'current': true,
        },
        {
          'id': 'def',
          'createdAt': '2026-08-01T10:00:00Z',
          'expiresAt': '2026-09-15T10:00:00Z',
          'lastUsedAt': '2026-08-20T08:00:00Z',
          'current': false,
        },
      ],
    });
    final sessions = await SessionsService.list();
    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/v0/auth/sessions');
    expect(sessions.map((s) => s.id), ['abc', 'def']);
    expect(sessions.map((s) => s.current), [true, false]);
    expect(sessions.first.createdAt, DateTime.utc(2026, 9, 1, 10));
    expect(sessions.first.lastUsedAt, DateTime.utc(2026, 9, 2, 11, 30));
  });

  test('an account with no sessions reads as an empty list', () async {
    answer(200, {'sessions': <Object>[]});
    expect(await SessionsService.list(), isEmpty);
  });

  test('revokes one session by its id', () async {
    answer(200, {'revoked': true});
    await SessionsService.revoke('abc');
    expect(requests.single.method, 'DELETE');
    expect(requests.single.url.path, '/api/v0/auth/sessions/abc');
  });

  test('revokes the others with the bulk DELETE', () async {
    answer(200, {'revoked': true});
    await SessionsService.revokeOthers();
    expect(requests.single.method, 'DELETE');
    expect(requests.single.url.path, '/api/v0/auth/sessions');
  });

  test("a refusal is a status, never the Quark's error text", () async {
    answer(404, {'error': 'session not found'});
    await expectLater(
      SessionsService.revoke('gone'),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
      ),
    );
    answer(500, {'error': 'failed to list sessions: database is locked'});
    await expectLater(SessionsService.list(), throwsA(isA<ApiException>()));
    await expectLater(
      SessionsService.revokeOthers(),
      throwsA(isA<ApiException>()),
    );
  });
}
