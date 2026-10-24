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
import 'package:quark/services/vault_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:sodium/sodium_sumo.dart' show SecureKey;
import 'package:quark_widgets/quark_widgets.dart' show VaultEntryDraft;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/auth_salt.dart';
import '../support/fake_vault.dart';
import '../support/secure_storage.dart';

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

/// #3022: a signed-in member changes their own password. #2430: the Quark is
/// sent the two passwords' auth keys, never either password. #2416: the chat
/// keys go in the same request, re-wrapped, so chat history survives.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final stored = <String, String>{};

  setUpAll(() {
    mockSecureStorage(stored);
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

  /// What the re-wrap answers with: [rewrapped], or null for an account with
  /// no chat keys.
  WrappedChatKeys? chatKeys;

  setUp(() async {
    stored.clear();
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'One', 'hostAddress': 'http://one.local'},
      ]),
      'activeHostIndex': 0,
    });
    await AppSettings.instance.load();
    await AppSettings.instance.setSessionToken('session-token');
    await AppSettings.instance.setUsername('grace');
    rewraps.clear();
    chatKeys = rewrapped;
    chatKeysForPasswordChange =
        ({
          required currentPassword,
          required newPassword,
          required authSalt,
        }) async {
          rewraps.add('$currentPassword/$newPassword/$authSalt');
          return chatKeys;
        };
  });

  tearDown(() {
    authHttpClientFactory = () => sharedHttpClient;
    chatKeysForPasswordChange =
        ChatKeysController.instance.keysForPasswordChange;
    vaultKeyFetch = VaultService.fetchKey;
  });

  /// The account's stored vault key; null for an account with no vault.
  WrappedVaultKey? storedVault;
  setUp(() {
    storedVault = null;
    vaultKeyFetch = ({sessionToken}) async => storedVault;
  });

  Future<void> change() => AuthService.changePassword(
    currentPassword: 'the-old-password',
    newPassword: 'brand-new-password',
  );

  Matcher refusesWith(String message) => throwsA(
    isA<MessageException>().having((e) => e.message, 'message', message),
  );

  test('sends both passwords as keys, with the chat keys re-wrapped, and '
      'keeps the session', () async {
    final client = _RecordingClient();
    final salts = AuthSaltClient(client);
    authHttpClientFactory = () => salts;

    await change();

    final request = client.requests.single;
    expect(request.method, 'PUT');
    expect(request.url.path, '/api/v0/auth/password');
    expect(request.headers['Authorization'], 'Bearer session-token');
    expect(jsonDecode(request.body), {
      'password': await testAuthKey('the-old-password'),
      'newAuthKey': await testAuthKey('brand-new-password'),
      'chatKeys': rewrapped.toJson(),
    });
    // #2430: neither password leaves the app.
    expect(request.body, isNot(contains('the-old-password')));
    expect(request.body, isNot(contains('brand-new-password')));
    expect(salts.asked, everyElement('grace'));
    // #2416: re-wrapped under the salt the new auth key was derived with.
    expect(rewraps, ['the-old-password/brand-new-password/$testAuthSalt']);
    expect(AppSettings.instance.sessionToken, 'session-token');
    expect(AppSettings.instance.username, 'grace');
  });

  test('an account with no chat keys sends none', () async {
    final client = _RecordingClient();
    authHttpClientFactory = () => AuthSaltClient(client);
    chatKeys = null;

    await change();

    final body = jsonDecode(client.requests.single.body) as Map;
    expect(body.keys, unorderedEquals(['password', 'newAuthKey']));
  });

  test('a current password that opens no keys stops before anything is '
      'sent', () async {
    final client = _RecordingClient();
    authHttpClientFactory = () => AuthSaltClient(client);
    chatKeysForPasswordChange =
        ({required currentPassword, required newPassword, required authSalt}) =>
            Future.error(const MessageException(Errors.wrongCurrentPassword));

    await expectLater(change(), refusesWith(Errors.wrongCurrentPassword));
    expect(client.requests, isEmpty);
  });

  test('a current password the Quark refuses reads as wrong, and the '
      'session stays', () async {
    final client = _RecordingClient(
      status: 403,
      body: '{"error":"incorrect password"}',
    );
    authHttpClientFactory = () => AuthSaltClient(client);

    await expectLater(change(), refusesWith(Errors.wrongCurrentPassword));
    expect(AppSettings.instance.sessionToken, 'session-token');
  });

  test(
    'any other refusal carries its status, never the Quark\'s text',
    () async {
      final client = _RecordingClient(
        status: 403,
        body: '{"error":"account disabled"}',
      );
      authHttpClientFactory = () => AuthSaltClient(client);

      await expectLater(
        change(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
    },
  );

  test('a session the Quark no longer honors is an expired session', () async {
    final client = _RecordingClient(
      status: 401,
      body: '{"error":"not authenticated"}',
    );
    authHttpClientFactory = () => AuthSaltClient(client);

    await expectLater(change(), throwsA(isA<UnauthorizedException>()));
  });

  test('too many attempts carries the 429', () async {
    final client = _RecordingClient(
      status: 429,
      body: '{"error":"too many attempts"}',
    );
    authHttpClientFactory = () => AuthSaltClient(client);

    await expectLater(
      change(),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 429)),
    );
    expect(
      Errors.message(const ApiException(429), 'change your password'),
      'Too many requests. Wait a moment and try again.',
    );
  });

  group('refused before anything is sent:', () {
    late _RecordingClient client;
    late AuthSaltClient salts;

    setUp(() {
      client = _RecordingClient();
      salts = AuthSaltClient(client);
      authHttpClientFactory = () => salts;
    });

    test('no session', () async {
      await AppSettings.instance.setSessionToken(null);

      await expectLater(change(), throwsA(isA<UnauthorizedException>()));
      expect(client.requests, isEmpty);
      expect(salts.asked, isEmpty);
      expect(rewraps, isEmpty);
    });

    test('an account with no auth key yet: sign in again first', () async {
      salts.legacy = true;

      await expectLater(change(), refusesWith(Errors.accountTooOld));
      expect(client.requests, isEmpty);
      expect(rewraps, isEmpty);
    });

    test('a Quark with no salt endpoint: update it', () async {
      salts.status = 404;

      await expectLater(change(), refusesWith(Errors.quarkTooOld));
      expect(client.requests, isEmpty);
    });
  });

  group('the vault key (#3461)', () {
    const cheap = KdfParams(
      opsLimit: 1,
      memLimit: 8192,
      alg: KdfParams.splitAlgorithm,
    );
    late AccountCrypto crypto;
    late SecureKey vaultKey;
    final phraseWrap = WrappedSecret(
      wrapped: Uint8List(72),
      salt: Uint8List(16),
    );

    setUp(() async {
      crypto = await AccountCrypto.load();
      vaultKey = crypto.generateVaultKey();
      addTearDown(vaultKey.dispose);
      final keys = crypto.deriveAuthKeys(
        'the-old-password',
        testAuthSalt,
        cheap,
      );
      addTearDown(keys.dispose);
      storedVault = WrappedVaultKey(
        byPassword: crypto.wrapVaultKey(
          vaultKey,
          keys.vaultWrapKey,
          testAuthSalt,
        ),
        byPhrase: phraseWrap,
        kdfParams: cheap,
      );
    });

    // #3648: the stored key is at [cheap], a cost a tampered Quark could
    // have lowered it to; the new wrap is at the standard cost regardless.
    test('goes in the same request, re-wrapped under the new password at '
        'the standard cost, the phrase wrap kept', () async {
      final client = _RecordingClient();
      authHttpClientFactory = () => AuthSaltClient(client);

      await change();

      final body = jsonDecode(client.requests.single.body) as Map;
      final sent = WrappedVaultKey.fromJson(
        body['vaultKey'] as Map<String, dynamic>,
      );
      expect(sent.kdfParams.toJson(), KdfParams.standard.split.toJson());
      expect(sent.byPhrase!.wrapped, phraseWrap.wrapped);
      final next = crypto.deriveAuthKeys(
        'brand-new-password',
        sent.byPassword.salt,
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
      // Neither the key nor anything that opens it went out.
      final raw = client.requests.single.body;
      expect(raw, isNot(contains(base64Encode(vaultKey.extractBytes()))));
      expect(
        raw,
        isNot(contains(base64Encode(next.vaultWrapKey.extractBytes()))),
      );
    });

    // #3461: setup re-confirms the login password, so the key the vault page
    // makes is one the next password change can open.
    for (final phrase in ['', 'apple-bread']) {
      final label = phrase.isEmpty ? 'without' : 'with';
      test('one set up on the vault page $label the phrase opens with the new '
          'password, and its item still decrypts', () async {
        final server = FakeVault()
          ..loginAuthKey = fakeLoginAuthKey(crypto, 'the-old-password');
        final page = server.controller(crypto);
        addTearDown(page.dispose);
        await page.load();
        await page.setUp('the-old-password', phrase: phrase);
        expect(page.formError, isNull);
        await page.saveDraft(
          const VaultEntryDraft(name: 'GitHub', password: 'p'),
        );
        page.lock();
        final made = server.key!;
        storedVault = made;
        final client = _RecordingClient();
        authHttpClientFactory = () => AuthSaltClient(client);

        await change();

        server.key = WrappedVaultKey.fromJson(
          (jsonDecode(client.requests.single.body) as Map)['vaultKey']
              as Map<String, dynamic>,
        );
        if (phrase.isEmpty) {
          expect(server.key!.byPhrase, isNull);
        } else {
          expect(server.key!.byPhrase!.wrapped, made.byPhrase!.wrapped);
          expect(server.key!.kdfParams.alg, KdfParams.phraseSplitAlgorithm);
        }
        final after = server.controller(crypto);
        addTearDown(after.dispose);
        await after.load();
        await after.unlock('brand-new-password');
        expect(after.formError, isNull);
        expect(after.entries.single.data.password, 'p');
      });
    }

    test('one the current password does not open is left out, and the change '
        'still goes', () async {
      final keys = crypto.deriveAuthKeys(
        'another-password',
        testAuthSalt,
        cheap,
      );
      addTearDown(keys.dispose);
      storedVault = WrappedVaultKey(
        byPassword: crypto.wrapVaultKey(
          vaultKey,
          keys.vaultWrapKey,
          testAuthSalt,
        ),
        byPhrase: null,
        kdfParams: cheap,
      );
      final client = _RecordingClient();
      authHttpClientFactory = () => AuthSaltClient(client);

      await change();

      final body = jsonDecode(client.requests.single.body) as Map;
      expect(body.containsKey('vaultKey'), isFalse);
    });

    test('a failed fetch stops the change before anything is sent', () async {
      vaultKeyFetch = ({sessionToken}) => Future.error(const ApiException(500));
      final client = _RecordingClient();
      authHttpClientFactory = () => AuthSaltClient(client);

      await expectLater(change(), throwsA(isA<ApiException>()));
      expect(client.requests, isEmpty);
    });
  });
}
