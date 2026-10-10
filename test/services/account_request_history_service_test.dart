import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/account_request_history_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The admin route the Recent decisions section reads (#2730).
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

  Matcher throwsStatus(int status) => throwsA(
    isA<ApiException>().having((e) => e.statusCode, 'status', status),
  );

  test('lists the decisions in the order the Quark gives them', () async {
    answer(200, [
      {
        'username': 'eli',
        'outcome': 'denied',
        'decidedBy': 'ada',
        'decidedAt': '2026-10-09T11:23:39Z',
      },
      {
        'username': 'grace',
        'outcome': 'approved',
        'decidedBy': 'ada',
        'decidedAt': '2026-10-08T09:00:00Z',
      },
    ]);

    final decisions = await AccountRequestHistoryService.list();

    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/v0/admin/account-requests/history');
    expect(decisions.map((d) => d.username), ['eli', 'grace']);
    expect(decisions.map((d) => d.approved), [false, true]);
    expect(decisions.first.decidedBy, 'ada');
  });

  test('an empty history is an empty list', () async {
    answer(200, <Object>[]);

    expect(await AccountRequestHistoryService.list(), isEmpty);
  });

  test('403 reads as a permission failure', () async {
    answer(403, {'error': 'admin only'});

    await expectLater(AccountRequestHistoryService.list(), throwsStatus(403));
  });

  // A 500 here carries a Go error's text, a file path included (#1622).
  test("a failure never passes the Quark's error text on", () async {
    answer(500, {'error': 'open /data/account-request-history.jsonl: denied'});

    await expectLater(AccountRequestHistoryService.list(), throwsStatus(500));
  });
}
