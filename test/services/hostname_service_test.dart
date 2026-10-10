import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/hostname_service.dart';
import 'package:quark/utils/error_text.dart';

/// #2344: the admin-only `/api/v0/hostname` routes, as the app reads them.
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

  /// The sentence a user would read for what [request] throws.
  Future<String> failure(Future<Object?> request) async {
    try {
      await request;
    } catch (error) {
      return Errors.message(error, 'rename this Quark');
    }
    fail('the request did not throw');
  }

  setUp(requests.clear);
  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  test('reads a Quark that can be renamed', () async {
    answer(200, {
      'available': true,
      'hostname': 'quark',
      'advertisedHostname': 'quark-2',
    });
    final status = await HostnameService.getStatus();
    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/v0/hostname');
    expect(status.available, isTrue);
    expect(status.hostname, 'quark');
    expect(status.advertisedHostname, 'quark-2');
    expect(status.networkName, 'quark-2');
  });

  test('reads a Quark that cannot, with the reason', () async {
    answer(200, {
      'available': false,
      'reason': 'unsupported_os',
      'hostname': 'quark',
    });
    final status = await HostnameService.getStatus();
    expect(status.available, isFalse);
    expect(status.reason, 'unsupported_os');
    expect(status.advertisedHostname, isEmpty);
    expect(status.networkName, 'quark');
  });

  test('sends the new name and reads what the device took', () async {
    answer(200, {
      'available': true,
      'hostname': 'kitchen',
      'advertisedHostname': 'kitchen-2',
    });
    final status = await HostnameService.setHostname('kitchen');
    expect(requests.single.method, 'PUT');
    expect(requests.single.url.path, '/api/v0/hostname');
    expect(jsonDecode(requests.single.body), {'hostname': 'kitchen'});
    expect(status.hostname, 'kitchen');
    expect(status.networkName, 'kitchen-2');
  });

  test("a 400 and a 409 carry the Quark's sentence", () async {
    answer(400, {'error': 'hostname must be 1 to 63 lowercase letters'});
    expect(
      await failure(HostnameService.setHostname('Kitchen')),
      'Hostname must be 1 to 63 lowercase letters.',
    );
    answer(409, {'error': "this Quark can't be renamed"});
    expect(
      await failure(HostnameService.setHostname('kitchen')),
      "This Quark can't be renamed.",
    );
  });

  test("a 500 does not put the helper's output in front of a user", () async {
    answer(500, {'error': 'set-hostname: exit status 1: hostnamectl: nope'});
    await expectLater(
      HostnameService.setHostname('kitchen'),
      throwsA(isA<ApiException>()),
    );
    final text = await failure(HostnameService.setHostname('kitchen'));
    expect(text, isNot(contains('hostnamectl')));
    expect(text, Errors.message(const ApiException(500), 'rename this Quark'));
  });
}
