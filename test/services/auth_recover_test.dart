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
/// phrase belongs to. #2430: it sends keys, never the phrase or the password.
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

  /// The recovery keys each re-wrap was handed.
  final recoveryKeysSeen = <String>[];

  setUp(() {
    rewraps.clear();
    unlocks.clear();
    recoveryKeysSeen.clear();
    chatKeysForRecovery =
        ({
          required username,
          required recoveryPhrase,
          recoveryKeys,
          newPhraseWrapKey,
          required newPassword,
          required authSalt,
        }) {
          rewraps.add('$username/$recoveryPhrase/$newPassword/$authSalt');
          recoveryKeysSeen.add(recoveryKeys!.authKey);
          return Future.value(rewrapped);
        };
    chatKeysOnSignIn =
        ({
          required password,
          phraseWrapKey,
          required sessionToken,
          authSalt,
        }) async {
          unlocks.add('$password/$sessionToken/$authSalt');
          return null;
        };
  });

  tearDown(() => authHttpClientFactory = () => sharedHttpClient);

  test('recovery names the account the phrase belongs to, and sends only '
      'keys', () async {
    final client = _RecordingClient();
    final salts = AuthSaltClient(client);
    authHttpClientFactory = () => salts;
    const phrase = 'apple-bread-cloud-delta-eagle-flame';

    final result = await AuthService.recover(
      username: 'grace',
      recoveryPhrase: phrase,
      newPassword: 'brand-new-password',
    );

    final request = client.requests.single;
    expect(request.url.path, '/api/v0/auth/recover');
    final recoveryKey = await testRecoveryKey(phrase);
    // #2430: the keys derived from the phrase and the new password, never
    // either one.
    expect(jsonDecode(request.body), {
      'username': 'grace',
      'recoveryKey': recoveryKey,
      'newAuthKey': await testAuthKey('brand-new-password'),
      'chatKeys': rewrapped.toJson(),
    });
    expect(request.body, isNot(contains('apple')));
    expect(request.body, isNot(contains('brand-new-password')));
    expect(salts.asked, ['grace']);
    expect(result.recoveryPhrase, isNull);
    expect(AppSettings.instance.sessionToken, 'new-token');
    // Recovery now names the account, so the app knows who is signed in.
    expect(AppSettings.instance.username, 'grace');
    // #2416: the keys were re-wrapped under the new password before the reset,
    // with the same recovery key, and chat unlocks with it afterwards.
    // #2430: both under the salt the new auth key was derived with.
    expect(rewraps, ['grace/$phrase/brand-new-password/$testAuthSalt']);
    expect(recoveryKeysSeen, [recoveryKey]);
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
            required authSalt,
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

  group('refused before anything is sent (#2430):', () {
    late _RecordingClient client;
    late AuthSaltClient salts;

    setUp(() {
      client = _RecordingClient();
      salts = AuthSaltClient(client);
      authHttpClientFactory = () => salts;
    });

    Future<LoginResult> recover() => AuthService.recover(
      username: 'grace',
      recoveryPhrase: 'apple-bread-cloud-delta-eagle-flame',
      newPassword: 'brand-new-password',
    );

    Matcher refusesWith(String message) => throwsA(
      isA<MessageException>().having((e) => e.message, 'message', message),
    );

    test('a Quark that does not report recovery keys: update it', () async {
      salts.legacyRecovery = null;

      await expectLater(recover(), refusesWith(Errors.quarkTooOld));
      expect(client.requests, isEmpty);
    });

    test('a Quark with no salt endpoint: update it', () async {
      salts.status = 404;

      await expectLater(recover(), refusesWith(Errors.quarkTooOld));
      expect(client.requests, isEmpty);
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
      AuthService.fetchRecoveryChatKeys(username: 'grace', recoveryKey: 'x'),
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
