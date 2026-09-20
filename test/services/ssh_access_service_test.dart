import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/ssh_access_service.dart';
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

  test('reads the status', () async {
    answer(200, {
      'available': true,
      'enabled': true,
      'keys': [
        {'type': 'ssh-ed25519', 'fingerprint': 'SHA256:abc', 'comment': 'me'},
      ],
    });
    final status = await SshAccessService.getStatus();
    expect(requests.single.url.path, '/api/v0/ssh/status');
    expect(status.available, isTrue);
    expect(status.enabled, isTrue);
    expect(status.keys.single.fingerprint, 'SHA256:abc');
  });

  test('removes a key by a fingerprint with a slash in it', () async {
    answer(200, {});
    await SshAccessService.removeKey('SHA256:a/b+c');
    expect(requests.single.method, 'DELETE');
    expect(requests.single.url.path, '/api/v0/ssh/keys');
    expect(requests.single.url.queryParameters['fingerprint'], 'SHA256:a/b+c');
  });

  test('sends the password in the body', () async {
    answer(200, {});
    await SshAccessService.setPassword('long enough password');
    expect(requests.single.method, 'PUT');
    expect(jsonDecode(requests.single.body), {
      'password': 'long enough password',
    });
  });

  test("a 409 carries the Quark's sentence; a 500 does not", () async {
    answer(409, {'error': 'that key is already allowed'});
    await expectLater(
      SshAccessService.addKey('ssh-ed25519 AAAA'),
      throwsA(isA<MessageException>()),
    );
    answer(500, {'error': 'ssh-access enable: exit status 1: ufw: not found'});
    await expectLater(
      SshAccessService.setEnabled(true),
      throwsA(isA<ApiException>()),
    );
  });
}
