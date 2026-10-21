import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/controllers/chat_keys_controller.dart';
import 'package:quark/models/account_keys.dart';
import 'package:quark/models/chat_keys.dart';
import 'package:quark/models/vault_key.dart';
import 'package:quark/services/account_crypto.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/chat_key_service.dart';
import 'package:quark/services/vault_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sodium/sodium_sumo.dart' show SecureKey;

import '../support/auth_salt.dart';

/// A Quark that answers every request with one canned response, and remembers
/// what it was asked.
class _RecordingClient extends http.BaseClient {
  _RecordingClient({this.status = 204, this.body = ''});

  final int status;
  final String body;
  final requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request as http.Request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      request: request,
    );
  }
}

/// #3530: keys made without a phrase wrap get one under the phrase the
/// account already has. The Quark checks that phrase's recovery key before
/// anything is stored, and is never sent the phrase, the password, a wrap key
/// or the vault key.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const phrase = 'apple-bread-cloud-delta-eagle-flame';
  const password = 'the-password';

  /// What the fake chat re-wrap hands back: recognizable bytes, not real
  /// crypto, which ChatKeysController's own tests cover.
  final rewrapped = WrappedChatKeys(
    publicKeys: ChatPublicKeys(
      boxPublicKey: Uint8List(32),
      signPublicKey: Uint8List(32),
    ),
    byPassword: WrappedSecret(wrapped: Uint8List(104), salt: Uint8List(16)),
    byPhrase: WrappedSecret(wrapped: Uint8List(104), salt: Uint8List(16)),
    kdfParams: KdfParams.standard.phraseSplit,
  );

  /// What the chat re-wrap answers with; null for an account with no chat
  /// keys.
  WrappedChatKeys? chatKeys;

  /// The password and phrase wrap key each chat re-wrap was handed.
  final chatRewraps = <(String, List<int>)>[];

  /// The account's stored vault key; null for an account with no vault.
  WrappedVaultKey? storedVault;

  late AccountCrypto crypto;
  late SecureKey vaultKey;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async => null);
    crypto = await AccountCrypto.load();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'One', 'hostAddress': 'http://one.local'},
      ]),
      'activeHostIndex': 0,
    });
    await AppSettings.instance.load();
    await AppSettings.instance.setSessionToken('session-token');
    await AppSettings.instance.setUsername('grace');
    chatRewraps.clear();
    chatKeys = rewrapped;
    chatKeysForPhrase =
        ({required password, required phraseWrapKey, required authSalt}) async {
          chatRewraps.add((password, phraseWrapKey.extractBytes()));
          return chatKeys;
        };
    vaultKey = crypto.generateVaultKey();
    final keys = crypto.deriveAuthKeys(
      password,
      testAuthSalt,
      KdfParams.standard,
    );
    storedVault = WrappedVaultKey(
      byPassword: crypto.wrapVaultKey(
        vaultKey,
        keys.vaultWrapKey,
        testAuthSalt,
      ),
      byPhrase: null,
      kdfParams: KdfParams.standard.split,
    );
    keys.dispose();
    vaultKeyFetch = ({sessionToken}) async => storedVault;
  });

  tearDown(() {
    vaultKey.dispose();
    authHttpClientFactory = () => sharedHttpClient;
    chatKeysForPhrase = ChatKeysController.instance.keysForPhrase;
    chatKeysFetch = ChatKeyService.fetchMine;
    vaultKeyFetch = VaultService.fetchKey;
    recoveryVaultKeyFetch = AuthService.fetchRecoveryVaultKey;
    chatKeysForRecovery = ChatKeysController.instance.keysForRecovery;
    chatKeysOnSignIn =
        ({required password, phraseWrapKey, required sessionToken, authSalt}) =>
            ChatKeysController.instance.signedIn(
              password: password,
              phraseWrapKey: phraseWrapKey,
              sessionToken: sessionToken,
              authSalt: authSalt,
            );
  });

  Future<void> add({String typed = phrase}) =>
      AuthService.addRecoveryPhrase(password: password, phrase: typed);

  Matcher refusesWith(String message) => throwsA(
    isA<MessageException>().having((e) => e.message, 'message', message),
  );

  /// [phrase]'s keys over [testAuthSalt], at the cost the app derives them.
  AuthKeys phraseKeys() {
    final keys = crypto.deriveRecoveryKeys(
      phrase,
      testAuthSalt,
      KdfParams.standard,
    );
    addTearDown(keys.dispose);
    return keys;
  }

  test('sends the phrase\'s recovery key as the current one, with both keys '
      'wrapped under the phrase, and nothing that opens them', () async {
    final client = _RecordingClient();
    authHttpClientFactory = () => AuthSaltClient(client);

    await add();

    final request = client.requests.single;
    expect(request.method, 'PUT');
    expect(request.url.path, '/api/v0/auth/recovery-key');
    expect(request.headers['Authorization'], 'Bearer session-token');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final recoveryKey = await testRecoveryKey(phrase);
    expect(body['currentRecoveryKey'], recoveryKey);
    expect(body['recoveryKey'], recoveryKey);
    expect(body.containsKey('password'), isFalse);
    expect(body['chatKeys'], rewrapped.toJson());
    final mine = phraseKeys();
    expect(chatRewraps.single.$1, password);
    expect(chatRewraps.single.$2, mine.wrapKey.extractBytes());

    final sent = WrappedVaultKey.fromJson(
      body['vaultKey'] as Map<String, dynamic>,
    );
    expect(sent.kdfParams.alg, KdfParams.phraseSplitAlgorithm);
    final opened = crypto.unwrapVaultKey(
      sent.byPhrase!,
      mine.vaultWrapKey,
      wrongSecret: 'x',
    );
    addTearDown(opened.dispose);
    expect(opened.extractBytes(), vaultKey.extractBytes());

    final raw = request.body;
    expect(raw, isNot(contains('apple')));
    expect(raw, isNot(contains(password)));
    for (final secret in [
      vaultKey.extractBytes(),
      mine.wrapKey.extractBytes(),
      mine.vaultWrapKey.extractBytes(),
    ]) {
      expect(raw, isNot(contains(base64Encode(secret))));
    }
  });

  test('a phrase the Quark says is not the account\'s reads as that, and '
      'the app goes no further', () async {
    final client = _RecordingClient(
      status: 403,
      body: '{"error":"invalid recovery phrase"}',
    );
    authHttpClientFactory = () => AuthSaltClient(client);

    await expectLater(
      add(typed: 'acid-bread-cloud-delta-eagle-flame'),
      refusesWith(Errors.recoveryPhraseNotTheAccounts),
    );
    expect(client.requests, hasLength(1));
    expect(
      Errors.message(
        const MessageException(Errors.recoveryPhraseNotTheAccounts),
        'add your recovery phrase',
      ),
      Errors.recoveryPhraseNotTheAccounts,
    );
  });

  test(
    'a password that opens neither key stops before anything is sent',
    () async {
      chatKeys = null;
      final other = crypto.deriveAuthKeys(
        'another-password',
        testAuthSalt,
        KdfParams.standard,
      );
      storedVault = WrappedVaultKey(
        byPassword: crypto.wrapVaultKey(
          vaultKey,
          other.vaultWrapKey,
          testAuthSalt,
        ),
        byPhrase: null,
        kdfParams: KdfParams.standard.split,
      );
      other.dispose();
      final client = _RecordingClient();
      authHttpClientFactory = () => AuthSaltClient(client);

      await expectLater(add(), refusesWith(Errors.vaultWrongPassword));
      expect(client.requests, isEmpty);
    },
  );

  test(
    'a wrong password for the chat keys stops before anything is sent',
    () async {
      chatKeysForPhrase =
          ({required password, required phraseWrapKey, required authSalt}) =>
              Future.error(
                const MessageException(Errors.chatKeysWrongPassword),
              );
      final client = _RecordingClient();
      authHttpClientFactory = () => AuthSaltClient(client);

      await expectLater(add(), refusesWith(Errors.chatKeysWrongPassword));
      expect(client.requests, isEmpty);
    },
  );

  test('an account with neither key sends nothing', () async {
    chatKeys = null;
    storedVault = null;
    final client = _RecordingClient();
    authHttpClientFactory = () => AuthSaltClient(client);

    await add();

    expect(client.requests, isEmpty);
  });

  test('signed out is refused before anything is derived', () async {
    await AppSettings.instance.setSessionToken(null);
    final client = _RecordingClient();
    authHttpClientFactory = () => AuthSaltClient(client);

    await expectLater(add(), throwsA(isA<UnauthorizedException>()));
    expect(client.requests, isEmpty);
    expect(chatRewraps, isEmpty);
  });

  test('says which keys have no phrase wrap', () async {
    WrappedChatKeys? storedChat = WrappedChatKeys(
      publicKeys: rewrapped.publicKeys,
      byPassword: rewrapped.byPassword,
      byPhrase: null,
      kdfParams: KdfParams.standard.split,
    );
    chatKeysFetch = ({sessionToken}) async => storedChat;

    expect(await AuthService.missingPhraseWraps(), (chat: true, vault: true));

    storedChat = rewrapped;
    storedVault = null;
    expect(await AuthService.missingPhraseWraps(), (chat: false, vault: false));
  });

  test('afterwards a recovery with the phrase carries the vault key over to '
      'the new password', () async {
    final client = _RecordingClient();
    authHttpClientFactory = () => AuthSaltClient(client);
    await add();
    // The Quark stores what the request carried.
    storedVault = WrappedVaultKey.fromJson(
      (jsonDecode(client.requests.single.body) as Map)['vaultKey']
          as Map<String, dynamic>,
    );
    recoveryVaultKeyFetch =
        ({required username, recoveryPhrase, recoveryKey}) async => storedVault;
    chatKeysForRecovery =
        ({
          required username,
          required recoveryPhrase,
          recoveryKeys,
          newPhraseWrapKey,
          required newPassword,
          required authSalt,
        }) async => rewrapped;
    chatKeysOnSignIn =
        ({
          required password,
          phraseWrapKey,
          required sessionToken,
          authSalt,
        }) async => null;
    await AppSettings.instance.setSessionToken(null);
    final recovery = _RecordingClient(status: 200, body: '{"token":"new"}');
    authHttpClientFactory = () => AuthSaltClient(recovery);

    await AuthService.recover(
      username: 'grace',
      recoveryPhrase: phrase,
      newPassword: 'brand-new-password',
    );

    final sent = WrappedVaultKey.fromJson(
      (jsonDecode(recovery.requests.single.body) as Map)['vaultKey']
          as Map<String, dynamic>,
    );
    final next = crypto.deriveAuthKeys(
      'brand-new-password',
      testAuthSalt,
      sent.kdfParams,
    );
    addTearDown(next.dispose);
    final opened = crypto.unwrapVaultKey(
      sent.byPassword,
      next.vaultWrapKey,
      wrongSecret: 'x',
    );
    addTearDown(opened.dispose);
    expect(opened.extractBytes(), vaultKey.extractBytes());
    // Lets the sign-in's chat unlock finish against the fake.
    await pumpEventQueue();
  });
}
