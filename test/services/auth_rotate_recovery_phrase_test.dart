import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/controllers/chat_keys_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/vault_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/auth_salt.dart';
import '../support/secure_storage.dart';

/// #3183: an account made before 16-word phrases still holds a 6-word one.
/// Settings asks its owner to make a new one, which goes through
/// `PUT /auth/recovery-key` with the password re-confirmed and the phrase's
/// length beside its key, and the prompt clears once the Quark has it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final settings = AppSettings.instance;
  final requests = <http.Request>[];

  /// What `PUT /auth/recovery-key` answers.
  late http.Response rotation;

  /// What `GET /auth/status` says about the phrase; null leaves it out, as
  /// an older Quark does.
  late bool? shortAfter;

  setUp(() async {
    mockSecureStorage();
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'One', 'hostAddress': 'http://one.local'},
      ]),
      'activeHostIndex': 0,
    });
    await settings.load();
    await settings.setSessionToken('session-token');
    await settings.setUsername('grace');
    settings.shortRecoveryPhrase.value = true;
    requests.clear();
    rotation = http.Response('', 204);
    shortAfter = false;
    final client = AuthSaltClient(
      MockClient((request) async {
        requests.add(request);
        return switch (request.url.path) {
          '/api/v0/auth/recovery-key' => rotation,
          '/api/v0/auth/status' => http.Response(
            jsonEncode({
              'setup': true,
              'username': 'grace',
              'shortRecoveryPhrase': ?shortAfter,
            }),
            200,
          ),
          _ => http.Response('{}', 404),
        };
      }),
    );
    authHttpClientFactory = () => client;
    sharedHttpClientFactory = () => client;
    resetSharedHttpClient();
    chatKeysOnSignIn =
        ({
          required password,
          phraseWrapKey,
          required sessionToken,
          authSalt,
        }) async => null;
    vaultKeyFetch = ({sessionToken}) async => null;
  });

  tearDown(() {
    authHttpClientFactory = () => sharedHttpClient;
    sharedHttpClientFactory = buildLocalTrustHttpClient;
    resetSharedHttpClient();
    chatKeysOnSignIn =
        ({required password, phraseWrapKey, required sessionToken, authSalt}) =>
            ChatKeysController.instance.signedIn(
              password: password,
              phraseWrapKey: phraseWrapKey,
              sessionToken: sessionToken,
              authSalt: authSalt,
            );
    vaultKeyFetch = VaultService.fetchKey;
    settings.shortRecoveryPhrase.value = false;
  });

  test('registers a 16-word phrase with its length and clears the '
      'prompt', () async {
    final phrase = await AuthService.rotateRecoveryPhrase(
      password: 'the-password',
    );

    expect(phrase.split('-'), hasLength(16));
    final put = requests.singleWhere(
      (r) => r.url.path == '/api/v0/auth/recovery-key',
    );
    expect(put.method, 'PUT');
    expect(put.headers['Authorization'], 'Bearer session-token');
    expect(jsonDecode(put.body), {
      'password': await testAuthKey('the-password'),
      'recoveryKey': await testRecoveryKey(phrase),
      'recoveryPhraseWords': 16,
    });
    expect(put.body, isNot(contains(phrase)));
    expect(put.body, isNot(contains('the-password')));
    expect(settings.shortRecoveryPhrase.value, isFalse);
  });

  test('a wrong password reads as one, and the prompt stays', () async {
    rotation = http.Response('{"error":"incorrect password"}', 403);

    await expectLater(
      AuthService.rotateRecoveryPhrase(password: 'not-it'),
      throwsA(
        isA<MessageException>().having(
          (e) => e.message,
          'message',
          Errors.wrongCurrentPassword,
        ),
      ),
    );
    expect(settings.shortRecoveryPhrase.value, isTrue);
  });

  test('reads shortRecoveryPhrase from the status, false when '
      'absent', () async {
    shortAfter = true;
    expect((await AuthService.checkStatus()).shortRecoveryPhrase, isTrue);
    shortAfter = null;
    expect((await AuthService.checkStatus()).shortRecoveryPhrase, isFalse);
  });
}
