import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/models/account_keys.dart';
import 'package:quark/models/chat_keys.dart';
import 'package:quark/models/vault_key.dart';
import 'package:quark/services/account_crypto.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
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

  final stored = <String, String>{};

  setUpAll(() {
    mockSecureStorage(stored);
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

  tearDown(() {
    authHttpClientFactory = () => sharedHttpClient;
    recoveryVaultKeyFetch = AuthService.fetchRecoveryVaultKey;
  });

  /// The account's stored vault key; null for an account with no vault.
  WrappedVaultKey? storedVault;

  /// What each vault key fetch was sent in the phrase's place.
  final vaultFetches = <String?>[];
  setUp(() {
    storedVault = null;
    vaultFetches.clear();
    recoveryVaultKeyFetch =
        ({required username, recoveryPhrase, recoveryKey}) async {
          vaultFetches.add(recoveryKey);
          return storedVault;
        };
  });

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

  group('the vault key (#3461)', () {
    const phrase = 'apple-bread-cloud-delta-eagle-flame';
    late AccountCrypto crypto;
    late SecureKey vaultKey;

    setUp(() async {
      crypto = await AccountCrypto.load();
      vaultKey = crypto.generateVaultKey();
      addTearDown(vaultKey.dispose);
    });

    /// The vault key wrapped as the vault page and a phrase rotation leave
    /// it: under some old password, and under [phrase] when [withPhrase].
    WrappedVaultKey wrapped({required bool withPhrase}) {
      final old = crypto.deriveAuthKeys(
        'lost password',
        testAuthSalt,
        KdfParams.standard,
      );
      final mine = crypto.deriveRecoveryKeys(
        phrase,
        testAuthSalt,
        KdfParams.standard,
      );
      addTearDown(old.dispose);
      addTearDown(mine.dispose);
      return WrappedVaultKey(
        byPassword: crypto.wrapVaultKey(
          vaultKey,
          old.vaultWrapKey,
          testAuthSalt,
        ),
        byPhrase: withPhrase
            ? crypto.wrapVaultKey(vaultKey, mine.vaultWrapKey, testAuthSalt)
            : null,
        kdfParams: withPhrase
            ? KdfParams.standard.phraseSplit
            : KdfParams.standard.split,
      );
    }

    Future<http.Request> recover() async {
      final client = _RecordingClient();
      authHttpClientFactory = () => AuthSaltClient(client);
      await AuthService.recover(
        username: 'grace',
        recoveryPhrase: phrase,
        newPassword: 'brand-new-password',
      );
      return client.requests.single;
    }

    test('opened with the phrase goes in the same request, under the new '
        'password and the same phrase', () async {
      storedVault = wrapped(withPhrase: true);

      final request = await recover();

      expect(vaultFetches, [await testRecoveryKey(phrase)]);
      final sent = WrappedVaultKey.fromJson(
        (jsonDecode(request.body) as Map)['vaultKey'] as Map<String, dynamic>,
      );
      expect(sent.kdfParams.alg, KdfParams.phraseSplitAlgorithm);
      final password = crypto.deriveAuthKeys(
        'brand-new-password',
        testAuthSalt,
        sent.kdfParams,
      );
      final mine = crypto.deriveRecoveryKeys(
        phrase,
        testAuthSalt,
        sent.kdfParams,
      );
      addTearDown(password.dispose);
      addTearDown(mine.dispose);
      for (final (wrap, key) in [
        (sent.byPassword, password.vaultWrapKey),
        (sent.byPhrase!, mine.vaultWrapKey),
      ]) {
        final opened = crypto.unwrapVaultKey(wrap, key, wrongSecret: 'x');
        addTearDown(opened.dispose);
        expect(opened.extractBytes(), vaultKey.extractBytes());
      }
      expect(
        request.body,
        isNot(contains(base64Encode(vaultKey.extractBytes()))),
      );
    });

    test('one set up on the vault page with the phrase is carried over, and '
        'its items still open', () async {
      final server = FakeVault();
      final page = server.controller(crypto, kdfParams: KdfParams.standard);
      addTearDown(page.dispose);
      await page.load();
      // Typed with capitals: the wrap is under the normalized phrase.
      await page.setUp(
        'lost password',
        phrase: 'Apple-Bread-Cloud-Delta-Eagle-Flame',
      );
      await page.saveDraft(
        const VaultEntryDraft(name: 'GitHub', password: 'p'),
      );
      page.lock();
      storedVault = server.key;

      final request = await recover();

      server.key = WrappedVaultKey.fromJson(
        (jsonDecode(request.body) as Map)['vaultKey'] as Map<String, dynamic>,
      );
      expect(server.key!.byPhrase, isNotNull);
      final after = server.controller(crypto);
      addTearDown(after.dispose);
      await after.load();
      await after.unlock('brand-new-password');
      expect(after.formError, isNull);
      expect(after.entries.single.data.password, 'p');
    });

    test(
      'with no phrase wrap is left out, and the recovery still goes',
      () async {
        storedVault = wrapped(withPhrase: false);

        final request = await recover();

        expect(
          (jsonDecode(request.body) as Map).containsKey('vaultKey'),
          isFalse,
        );
        expect(AppSettings.instance.sessionToken, 'new-token');
      },
    );

    test('an account with no vault sends none', () async {
      final request = await recover();

      expect(vaultFetches, hasLength(1));
      expect(
        (jsonDecode(request.body) as Map).containsKey('vaultKey'),
        isFalse,
      );
    });

    test('the fetch goes to its own route with the same credential', () async {
      final requests = <http.Request>[];
      authHttpClientFactory = () => MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 404);
      });

      expect(
        await AuthService.fetchRecoveryVaultKey(
          username: 'grace',
          recoveryKey: 'k',
        ),
        isNull,
      );
      expect(requests.single.url.path, '/api/v0/auth/recover/vault-key');
      expect(jsonDecode(requests.single.body), {
        'username': 'grace',
        'recoveryKey': 'k',
      });
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
