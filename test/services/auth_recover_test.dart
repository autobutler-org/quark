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

  setUp(() {
    rewraps.clear();
    unlocks.clear();
    chatKeysForRecovery =
        ({required username, required recoveryPhrase, required newPassword}) {
          rewraps.add('$username/$recoveryPhrase/$newPassword');
          return Future.value(rewrapped);
        };
    chatKeysOnSignIn =
        ({required password, recoveryPhrase, required sessionToken}) async {
          unlocks.add('$password/$sessionToken');
        };
  });

  tearDown(() => authHttpClientFactory = () => sharedHttpClient);

  test('recovery names the account the phrase belongs to', () async {
    final client = _RecordingClient();
    authHttpClientFactory = () => client;

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
      'newPassword': 'brand-new-password',
      'chatKeys': rewrapped.toJson(),
    });
    expect(AppSettings.instance.sessionToken, 'new-token');
    // Recovery now names the account, so the app knows who is signed in.
    expect(AppSettings.instance.username, 'grace');
    // #2416: the keys were re-wrapped under the new password before the reset,
    // and chat unlocks with it afterwards.
    expect(rewraps, [
      'grace/apple-bread-cloud-delta-eagle-flame/brand-new-password',
    ]);
    await pumpEventQueue();
    expect(unlocks, ['brand-new-password/new-token']);
  });

  test(
    'a phrase that opens no keys stops before the password changes',
    () async {
      final client = _RecordingClient();
      authHttpClientFactory = () => client;
      chatKeysForRecovery =
          ({
            required username,
            required recoveryPhrase,
            required newPassword,
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
