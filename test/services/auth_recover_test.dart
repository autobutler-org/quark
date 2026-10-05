import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/models/chat_keys.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/auth_salt.dart';

/// A Quark that answers every request with one canned response, and remembers
/// what it was asked.
class _RecordingClient extends http.BaseClient {
  final requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request as http.Request);
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"token":"new-token"}')),
      200,
      request: request,
    );
  }
}

/// #1900: with more than one account, recovery has to say which account the
/// phrase belongs to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final stored = <String, String>{};

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async {
          final key = call.arguments['key'] as String?;
          switch (call.method) {
            case 'read':
              return stored[key];
            case 'write':
              stored[key!] = call.arguments['value'] as String;
              return null;
            case 'delete':
              stored.remove(key);
              return null;
            default:
              return null;
          }
        });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  setUp(() async {
    stored.clear();
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'One', 'hostAddress': 'http://one.local'},
      ]),
      'activeHostIndex': 0,
    });
    await AppSettings.instance.load();
  });

  /// What the fake re-wrap hands back: recognizable bytes, not real crypto,
  /// which ChatKeysController's own tests cover.
  final rewrapped = WrappedChatKeys(
    publicKeys: ChatPublicKeys(
      boxPublicKey: Uint8List(32),
      signPublicKey: Uint8List(32),
    ),
    byPassword: WrappedSecret(wrapped: Uint8List(104), salt: Uint8List(16)),
    byPhrase: WrappedSecret(wrapped: Uint8List(104), salt: Uint8List(16)),
    kdfParams: KdfParams.standard,
  );
  final rewraps = <String>[];
  final unlocks = <String>[];

  /// The recovery keys each re-wrap was handed, null for none.
  final recoveryKeysSeen = <String?>[];

  /// How many re-wraps were handed a new phrase's wrap key.
  var newPhraseKeys = 0;

  setUp(() {
    rewraps.clear();
    unlocks.clear();
    recoveryKeysSeen.clear();
    newPhraseKeys = 0;
    chatKeysForRecovery =
        ({
          required username,
          required recoveryPhrase,
          recoveryKeys,
          newPhraseWrapKey,
          required newPassword,
          authSalt,
        }) {
          rewraps.add('$username/$recoveryPhrase/$newPassword/$authSalt');
          recoveryKeysSeen.add(recoveryKeys?.authKey);
          if (newPhraseWrapKey != null) newPhraseKeys++;
          return Future.value(rewrapped);
        };
    chatKeysOnSignIn =
        ({
          required password,
          recoveryPhrase,
          phraseWrapKey,
          required sessionToken,
          authSalt,
        }) async {
          unlocks.add('$password/$sessionToken/$authSalt');
          return null;
        };
  });

  tearDown(() => authHttpClientFactory = () => sharedHttpClient);

  test('recovery names the account the phrase belongs to, and a Quark that '
      'does not report recovery keys still gets the phrase', () async {
    final client = _RecordingClient();
    final salts = AuthSaltClient(client);
    authHttpClientFactory = () => salts;

    await AuthService.recover(
      username: 'grace',
      recoveryPhrase: 'apple-bread-cloud-delta-eagle-flame',
      newPassword: 'brand-new-password',
    );

    final request = client.requests.single;
    expect(request.url.path, '/api/v0/auth/recover');
    expect(jsonDecode(request.body), {
      'username': 'grace',
      'recoveryPhrase': 'apple-bread-cloud-delta-eagle-flame',
      // #2430: the key derived from the new password, never the password.
      'newAuthKey': await testAuthKey('brand-new-password'),
      'chatKeys': rewrapped.toJson(),
    });
    expect(salts.asked, ['grace']);
    expect(AppSettings.instance.signsInWithAuthKey('grace'), isTrue);
    expect(AppSettings.instance.sessionToken, 'new-token');
    // Recovery now names the account, so the app knows who is signed in.
    expect(AppSettings.instance.username, 'grace');
    // #2416: the keys were re-wrapped under the new password before the reset,
    // and chat unlocks with it afterwards.
    // #2430: both under the salt the new auth key was derived with.
    expect(rewraps, [
      'grace/apple-bread-cloud-delta-eagle-flame/brand-new-password/'
          '$testAuthSalt',
    ]);
    await pumpEventQueue();
    expect(unlocks, ['brand-new-password/new-token/$testAuthSalt']);
  });

  test(
    'a phrase that opens no keys stops before the password changes',
    () async {
      final client = _RecordingClient();
      authHttpClientFactory = () => AuthSaltClient(client);
      chatKeysForRecovery =
          ({
            required username,
            required recoveryPhrase,
            recoveryKeys,
            newPhraseWrapKey,
            required newPassword,
            authSalt,
          }) => Future.error(const MessageException('invalid recovery phrase'));

      await expectLater(
        AuthService.recover(
          username: 'grace',
          recoveryPhrase: 'wrong',
          newPassword: 'brand-new-password',
        ),
        throwsA(isA<MessageException>()),
      );
      expect(client.requests, isEmpty);
    },
  );

  group('recovery keys (#2430):', () {
    const phrase = 'apple-bread-cloud-delta-eagle-flame';
    late _RecordingClient client;
    late AuthSaltClient salts;

    setUp(() {
      client = _RecordingClient();
      salts = AuthSaltClient(client);
      authHttpClientFactory = () => salts;
    });

    Future<LoginResult> recover() => AuthService.recover(
      username: 'grace',
      recoveryPhrase: phrase,
      newPassword: 'brand-new-password',
    );

    Map<String, dynamic> sent() =>
        jsonDecode(client.requests.single.body) as Map<String, dynamic>;

    test('an account with a recovery key is sent the key, not the phrase, '
        'and keeps its phrase', () async {
      salts.legacyRecovery = false;

      final result = await recover();

      final recoveryKey = await testRecoveryKey(phrase);
      expect(sent(), {
        'username': 'grace',
        'recoveryKey': recoveryKey,
        'newAuthKey': await testAuthKey('brand-new-password'),
        'chatKeys': rewrapped.toJson(),
      });
      expect(client.requests.single.body, isNot(contains('apple')));
      // The re-wrap fetched and opened with the same key.
      expect(recoveryKeysSeen, [recoveryKey]);
      expect(newPhraseKeys, 0);
      expect(result.recoveryPhrase, isNull);
      expect(AppSettings.instance.hasRecoveryKey('grace'), isTrue);
    });

    test('an account without one sends its phrase once, and is given a new '
        'one', () async {
      salts.legacyRecovery = true;

      final result = await recover();

      final body = sent();
      expect(body['recoveryPhrase'], phrase);
      expect(body['newAuthKey'], await testAuthKey('brand-new-password'));
      expect(body.containsKey('recoveryKey'), isFalse);
      final next = result.recoveryPhrase!;
      expect(next, isNot(phrase));
      expect(body['newRecoveryKey'], await testRecoveryKey(next));
      expect(client.requests.single.body, isNot(contains(next)));
      expect(newPhraseKeys, 1);
      expect(AppSettings.instance.hasRecoveryKey('grace'), isTrue);
    });

    for (final claim in [true, null]) {
      test('once this Quark has a recovery key, a claim of '
          '${claim == null ? 'no field' : 'legacyRecovery'} is refused the '
          'phrase', () async {
        salts.legacyRecovery = false;
        await recover();
        client.requests.clear();
        salts.legacyRecovery = claim;

        await expectLater(
          recover(),
          throwsA(
            isA<MessageException>().having(
              (e) => e.message,
              'message',
              Errors.recoveryPhraseDowngradeRefused,
            ),
          ),
        );
        expect(client.requests, isEmpty);
        expect(rewraps, hasLength(1));
      });
    }

    test('a Quark with no salt endpoint is refused it too', () async {
      await AppSettings.instance.rememberRecoveryKey('grace');
      salts.status = 404;

      await expectLater(recover(), throwsA(isA<MessageException>()));
      expect(client.requests, isEmpty);
    });

    test('a failed recovery remembers nothing', () async {
      salts.legacyRecovery = true;
      authHttpClientFactory = () => AuthSaltClient(
        MockClient((_) async => http.Response('{"error":"nope"}', 400)),
        legacyRecovery: true,
      );

      await expectLater(recover(), throwsA(isA<MessageException>()));
      expect(AppSettings.instance.hasRecoveryKey('grace'), isFalse);
    });
  });

  test('the recovery key fetch sends no session and passes on the Quark\'s '
      'text', () async {
    final requests = <http.Request>[];
    authHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode({'error': 'invalid recovery phrase'}),
        400,
      );
    });

    await expectLater(
      AuthService.fetchRecoveryChatKeys(username: 'grace', recoveryPhrase: 'x'),
      throwsA(
        isA<MessageException>().having(
          (e) => e.message,
          'message',
          'invalid recovery phrase',
        ),
      ),
    );
    expect(requests.single.url.path, '/api/v0/auth/recover/keys');
    expect(requests.single.headers.containsKey('Authorization'), isFalse);
  });
}
