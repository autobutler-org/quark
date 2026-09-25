import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/models/chat_keys.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/chat_key_service.dart';

/// The chat key routes' wire shapes (#2416).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <http.Request>[];

  void answer(int status, Object? body) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode(body), status);
    });
  }

  final keys = WrappedChatKeys(
    publicKeys: ChatPublicKeys(
      boxPublicKey: Uint8List(32)..[0] = 1,
      signPublicKey: Uint8List(32)..[0] = 2,
    ),
    byPassword: WrappedSecret(wrapped: Uint8List(104), salt: Uint8List(16)),
    byPhrase: null,
    kdfParams: KdfParams.standard,
  );

  setUp(requests.clear);
  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  test('no keys yet reads as null, not an error', () async {
    answer(404, {'error': 'no chat keys for that account'});

    expect(await ChatKeyService.fetchMine(), isNull);
    expect(await ChatKeyService.fetchPublic(7), isNull);
    expect(requests.map((r) => r.url.path), [
      '/api/v0/chat/keys/me',
      '/api/v0/chat/keys/7',
    ]);
  });

  test('stores keys as base64 with an explicit session', () async {
    answer(200, keys.toJson());

    await ChatKeyService.putMine(keys, sessionToken: 'fresh');

    final request = requests.single;
    expect(request.method, 'PUT');
    expect(request.headers['Authorization'], 'Bearer fresh');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body.containsKey('wrappedByPhrase'), isFalse);
    expect(
      WrappedChatKeys.fromJson(body).publicKeys.signPublicKey,
      keys.publicKeys.signPublicKey,
    );
  });
}
