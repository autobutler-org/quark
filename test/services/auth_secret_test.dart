import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/controllers/chat_keys_controller.dart';
import 'package:quark/models/chat_keys.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_secret.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/services/users_service.dart';
import 'package:quark/services/vault_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/auth_salt.dart';

const _password = 'correct horse battery staple';

/// A Quark that records every request it is sent and answers the salt
/// endpoint as configured.
class _FakeQuark {
  final requests = <http.Request>[];

  /// The salt endpoint's status: 200, or what a Quark without one answers.
  int saltStatus = 200;

  /// What a 2xx salt answer carries when it is not the salt.
  String? saltBody;

  bool legacy = false;

  /// Whether the account has no recovery key yet, reported by the salt
  /// endpoint and the sign-in; null leaves the field out, as a Quark from
  /// before #2430 does.
  bool? legacyRecovery = false;

  /// What `PUT /auth/recovery-key` answers.
  int rotationStatus = 204;

  /// The account's stored chat keys, as `/chat/keys/me` keeps them.
  Map<String, dynamic>? chatKeys;

  late final http.Client client = MockClient((request) async {
    final path = request.url.path;
    if (path == '/api/v0/auth/salt') {
      requests.add(request);
      final body =
          saltBody ??
          jsonEncode({
            'salt': base64Encode(testAuthSalt),
            'legacy': legacy,
            'legacyRecovery': ?legacyRecovery,
          });
      return http.Response(saltStatus == 200 ? body : '{}', saltStatus);
    }
    requests.add(request);
    final sent = request.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    switch (path) {
      case '/api/v0/auth/login':
        if (sent.containsKey('password')) legacy = false;
        return http.Response(
          jsonEncode({'token': 'session', 'legacyRecovery': ?legacyRecovery}),
          200,
        );
      case '/api/v0/auth/recover':
        chatKeys = sent['chatKeys'] as Map<String, dynamic>?;
        if (sent.containsKey('newRecoveryKey')) legacyRecovery = false;
        return http.Response('{"token":"session"}', 200);
      case '/api/v0/auth/recover/keys':
        return chatKeys == null
            ? http.Response('{}', 404)
            : http.Response(jsonEncode(chatKeys), 200);
      case '/api/v0/auth/recovery-key':
        if (rotationStatus == 204) {
          chatKeys = sent['chatKeys'] as Map<String, dynamic>? ?? chatKeys;
          legacyRecovery = false;
        }
        return http.Response('', rotationStatus);
      case '/api/v0/chat/keys/me':
        if (request.method == 'PUT') {
          chatKeys = sent;
          return http.Response('', 204);
        }
        return chatKeys == null
            ? http.Response('{}', 404)
            : http.Response(jsonEncode(chatKeys), 200);
      case '/api/v0/auth/setup':
        return http.Response('{"token":"session"}', 200);
      case '/api/v0/auth/request-account':
        return http.Response('{}', 201);
      case '/api/v0/admin/users':
        return http.Response(
          jsonEncode({
            'id': 2,
            'username': sent['username'],
            'isAdmin': false,
            'status': 'active',
            'createdAt': '2026-09-14T12:00:00Z',
          }),
          201,
        );
      case '/api/v0/storage/devices/snapshot-backup':
        return http.Response('{"data":{"jobId":"job-1"}}', 200);
      default:
        return http.Response('{}', 200);
    }
  });

  /// Everything but the salt lookups.
  List<http.Request> get sent =>
      requests.where((r) => r.url.path != '/api/v0/auth/salt').toList();

  Map<String, dynamic> get lastBody =>
      jsonDecode(sent.last.body) as Map<String, dynamic>;
}

/// #2430: the app sends a key derived from the password, and the password or
/// the phrase only once, to move a legacy account to keys. Nothing else it
/// sends opens the chat keys, and what it cannot sign in to without them it
/// refuses before sending anything.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final settings = AppSettings.instance;
  late _FakeQuark quark;
  late ChatCrypto crypto;
  late String authKey;

  /// The auth salts [chatKeysOnSignIn] was handed, null for the first scheme.
  final chatSalts = <Uint8List?>[];

  /// What each [chatKeysOnSignIn] was handed for the phrase wrap: `key` for
  /// a generated phrase's wrap key, or null.
  final chatPhrases = <String?>[];

  setUpAll(() async {
    crypto = await ChatCrypto.load();
    authKey = await testAuthKey(_password);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'One', 'hostAddress': 'http://one.local'},
        {'name': 'Two', 'hostAddress': 'http://two.local'},
      ]),
      'activeHostIndex': 0,
    });
    await settings.load();
    quark = _FakeQuark();
    resetSharedHttpClient();
    sharedHttpClientFactory = () => quark.client;
    authHttpClientFactory = () => quark.client;
    chatSalts.clear();
    chatPhrases.clear();
    chatKeysOnSignIn =
        ({
          required password,
          phraseWrapKey,
          required sessionToken,
          authSalt,
        }) async {
          chatSalts.add(authSalt);
          chatPhrases.add(phraseWrapKey == null ? null : 'key');
          return null;
        };
  });

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
    authHttpClientFactory = () => sharedHttpClient;
  });

  Matcher refusesWith(String message) => throwsA(
    isA<MessageException>().having((e) => e.message, 'message', message),
  );

  Future<LoginResult> signIn() =>
      AuthService.login(username: 'grace', password: _password);

  test('a recorded sign-in holds neither the password nor anything that '
      'opens the chat keys', () async {
    WrappedChatKeys? stored;
    final keysController = ChatKeysController(
      loadCrypto: () async => crypto,
      fetchMine: ({sessionToken}) async => stored,
      putMine: (keys, {sessionToken}) async => stored = keys,
      readCache: (_) async => null,
      writeCache: (_, _) async {},
      deleteCache: (_) async {},
      persist: false,
    );
    final unlocked = Completer<void>();
    chatKeysOnSignIn =
        ({required password, phraseWrapKey, required sessionToken, authSalt}) =>
            keysController
                .signedIn(
                  password: password,
                  phraseWrapKey: phraseWrapKey,
                  sessionToken: sessionToken,
                  authSalt: authSalt,
                )
                .then((keys) {
                  unlocked.complete();
                  return keys;
                }, onError: unlocked.completeError);

    await signIn();
    await unlocked.future;

    final login = quark.sent.single;
    expect(login.url.path, '/api/v0/auth/login');
    expect(jsonDecode(login.body), {'username': 'grace', 'authKey': authKey});
    for (final request in quark.requests) {
      expect(request.url.toString(), isNot(contains(_password)));
      expect(request.body, isNot(contains(_password)));
      expect(request.headers.toString(), isNot(contains(_password)));
    }

    // Everything the Quark was sent, tried every way a wrap could be opened.
    final wrap = stored!.byPassword;
    final params = stored!.kdfParams;
    expect(params.isSplit, isTrue);
    final seen = <String>{
      for (final request in quark.requests) ...[
        ...request.url.queryParameters.values,
        if (request.body.isNotEmpty) ...[
          request.body,
          for (final value in (jsonDecode(request.body) as Map).values)
            '$value',
        ],
      ],
    };
    expect(seen, containsAll(['grace', authKey]));
    final wrong = throwsA(isA<MessageException>());
    for (final value in seen) {
      // As a password: the first scheme, and the split scheme.
      expect(() => crypto.unwrap(wrap, value, params), wrong, reason: value);
      final derived = crypto.deriveAuthKeys(value, wrap.salt, params);
      addTearDown(derived.dispose);
      expect(
        () => crypto.unwrapWithKey(wrap, derived.wrapKey),
        wrong,
        reason: value,
      );
      // As a raw key: its bytes, and what it decodes to.
      for (final bytes in [utf8.encode(value), _tryBase64(value)]) {
        if (bytes == null || bytes.length != 32) continue;
        final key = crypto.channelKeyFromBytes(Uint8List.fromList(bytes));
        addTearDown(key.dispose);
        expect(() => crypto.unwrapWithKey(wrap, key), wrong, reason: value);
      }
    }

    // The wrap key, derived here and never sent, does open it.
    final mine = crypto.deriveAuthKeys(_password, wrap.salt, params);
    addTearDown(mine.dispose);
    expect(mine.authKey, authKey);
    expect(
      crypto.unwrapWithKey(wrap, mine.wrapKey).box.publicKey,
      stored!.publicKeys.boxPublicKey,
    );
  });

  test('recorded recoveries and a rotation hold nothing that opens the '
      'phrase wrap or the password wrap', () async {
    // The real controller, over the Quark's real chat key routes.
    final keysController = ChatKeysController(
      loadCrypto: () async => crypto,
      readCache: (_) async => null,
      writeCache: (_, _) async {},
      deleteCache: (_) async {},
      persist: false,
    );
    chatKeysOnSignIn =
        ({required password, phraseWrapKey, required sessionToken, authSalt}) =>
            keysController.signedIn(
              password: password,
              phraseWrapKey: phraseWrapKey,
              sessionToken: sessionToken,
              authSalt: authSalt,
            );
    chatKeysForRecovery = keysController.keysForRecovery;
    addTearDown(
      () => chatKeysForRecovery = ChatKeysController.instance.keysForRecovery,
    );
    const second = 'second password, after a recovery';

    // 1. A sign-in the Quark says has no recovery key, as an admin-created
    // account's first is, makes the chat keys and gives the account a
    // phrase.
    quark.legacyRecovery = true;
    final p1 = (await AuthService.login(
      username: 'grace',
      password: _password,
    )).recoveryPhrase!;
    final p1Keys = WrappedChatKeys.fromJson(quark.chatKeys!);
    // 2. A recovery with that phrase sends only its key.
    quark.legacyRecovery = false;
    await AuthService.recover(
      username: 'grace',
      recoveryPhrase: p1,
      newPassword: second,
    );
    await pumpEventQueue();
    // 3. A sign-in the Quark again says has no recovery key rotates it.
    quark.legacyRecovery = true;
    final p2 = (await AuthService.login(
      username: 'grace',
      password: second,
    )).recoveryPhrase!;
    final p2Keys = WrappedChatKeys.fromJson(quark.chatKeys!);

    List<Map<String, dynamic>> bodies(String path) => quark.sent
        .where((r) => r.url.path == path)
        .map((r) => jsonDecode(r.body) as Map<String, dynamic>)
        .toList();
    final p1Key = await testRecoveryKey(p1);
    final p2Key = await testRecoveryKey(p2);
    final secondKey = await testAuthKey(second);
    expect(bodies('/api/v0/auth/recover/keys'), [
      {'username': 'grace', 'recoveryKey': p1Key},
    ]);
    final recovery = bodies('/api/v0/auth/recover').single;
    expect(recovery.keys, {
      'username',
      'recoveryKey',
      'newAuthKey',
      'chatKeys',
    });
    expect(recovery['recoveryKey'], p1Key);
    expect(recovery['newAuthKey'], secondKey);
    final rotations = bodies('/api/v0/auth/recovery-key');
    expect([for (final r in rotations) r['password']], [authKey, secondKey]);
    expect([for (final r in rotations) r['recoveryKey']], [p1Key, p2Key]);
    expect(rotations.last['chatKeys'], quark.chatKeys);
    expect(p2Keys.kdfParams.alg, KdfParams.phraseSplitAlgorithm);

    // No phrase or password ever went out, in any field of any request.
    for (final request in quark.requests) {
      final all = '${request.url} ${request.headers} ${request.body}';
      for (final secret in [p1, p2, _password, second]) {
        expect(all, isNot(contains(secret)), reason: request.url.path);
      }
      // The re-confirmation's field is named password, and carries a key.
      if (request.body.isNotEmpty &&
          request.url.path != '/api/v0/auth/recovery-key') {
        expect(
          (jsonDecode(request.body) as Map).keys,
          isNot(anyOf(contains('password'), contains('newPassword'))),
          reason: request.url.path,
        );
      }
      expect(request.body, isNot(contains('recoveryPhrase')));
    }

    // Every value the Quark was sent, tried every way a wrap could open: as a
    // passphrase under each scheme, and as a raw key.
    final wraps = [p1Keys.byPhrase!, p2Keys.byPhrase!, p2Keys.byPassword];
    for (final wrap in wraps) {
      // So one derivation per value serves every wrap.
      expect(wrap.salt, testAuthSalt);
    }
    final seen = <String>{
      for (final request in quark.requests) ...[
        ...request.url.queryParameters.values,
        if (request.body.isNotEmpty) ...[
          request.body,
          ..._strings(jsonDecode(request.body)),
        ],
      ],
    };
    expect(seen, containsAll([p1Key, p2Key, authKey, secondKey]));
    final wrong = throwsA(isA<MessageException>());
    final params = p2Keys.kdfParams;
    for (final value in seen) {
      final asPassword = crypto.deriveAuthKeys(value, testAuthSalt, params);
      final asPhrase = crypto.deriveRecoveryKeys(value, testAuthSalt, params);
      addTearDown(asPassword.dispose);
      addTearDown(asPhrase.dispose);
      final keys = [asPassword.wrapKey, asPhrase.wrapKey];
      for (final bytes in [utf8.encode(value), _tryBase64(value)]) {
        if (bytes == null || bytes.length != 32) continue;
        final key = crypto.channelKeyFromBytes(Uint8List.fromList(bytes));
        addTearDown(key.dispose);
        keys.add(key);
      }
      for (final wrap in wraps) {
        expect(() => crypto.unwrap(wrap, value, params), wrong, reason: value);
        for (final key in keys) {
          expect(() => crypto.unwrapWithKey(wrap, key), wrong, reason: value);
        }
      }
    }

    // The keys derived here, and never sent, do open them.
    final box = p2Keys.publicKeys.boxPublicKey;
    for (final (wrap, phrase) in [
      (p1Keys.byPhrase!, p1),
      (p2Keys.byPhrase!, p2),
    ]) {
      final mine = crypto.deriveRecoveryKeys(phrase, testAuthSalt, params);
      addTearDown(mine.dispose);
      expect(crypto.unwrapWithKey(wrap, mine.wrapKey).box.publicKey, box);
    }
    final mine = crypto.deriveAuthKeys(second, testAuthSalt, params);
    addTearDown(mine.dispose);
    expect(
      crypto.unwrapWithKey(p2Keys.byPassword, mine.wrapKey).box.publicKey,
      box,
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  group('giving an account with no recovery key one at sign-in (#2430)', () {
    // An account an admin created has none until its first sign-in, and one
    // whose phrase the Quark made has none either.
    setUp(() => quark.legacyRecovery = true);

    List<http.Request> rotations() => quark.sent
        .where((r) => r.url.path == '/api/v0/auth/recovery-key')
        .toList();

    test('registers a phrase the app made after the chat keys, and returns it '
        'only after a 204', () async {
      final result = await signIn();

      final put = rotations().single;
      expect(put.method, 'PUT');
      expect(put.headers['Authorization'], 'Bearer session');
      final phrase = result.recoveryPhrase!;
      expect(phrase.split('-'), hasLength(6));
      // The fake chat step has no keys to send, so none are.
      expect(jsonDecode(put.body), {
        'password': authKey,
        'recoveryKey': await testRecoveryKey(phrase),
      });
      expect(put.body, isNot(contains(phrase)));
      expect(put.body, isNot(contains(_password)));
      expect(chatPhrases, ['key']);
      // Held for the phrase step, as a first sign-in is.
      expect(settings.sessionToken, isNull);
    });

    test('a refused one returns nothing, keeps the session, and is tried '
        'again at the next sign-in', () async {
      quark.rotationStatus = 403;

      final result = await signIn();

      expect(result.recoveryPhrase, isNull);
      expect(settings.sessionToken, 'session');

      quark.rotationStatus = 204;
      expect((await signIn()).recoveryPhrase, isNotNull);
      expect(rotations(), hasLength(2));
    });
  });

  group('signing in', () {
    test('asks for the salt by the exact username, then sends the auth '
        'key', () async {
      await AuthService.login(username: 'Grace', password: _password);

      expect(quark.requests.first.url.queryParameters, {'username': 'Grace'});
      expect(quark.lastBody, {'username': 'Grace', 'authKey': authKey});
      await pumpEventQueue();
      expect(chatSalts, [testAuthSalt]);
    });

    test(
      'a failing salt endpoint fails the sign-in and sends nothing',
      () async {
        quark.saltStatus = 500;

        await expectLater(signIn(), throwsA(isA<ApiException>()));
        expect(quark.sent, isEmpty);
      },
    );
  });

  group('refused before anything but the salt goes out:', () {
    setUp(() async {
      await settings.setSessionToken('session');
      await settings.setUsername('grace');
    });

    /// Every flow that sends a password's key, each by [use].
    final flows = <String, (AuthSecretUse, Future<void> Function())>{
      'sign-in': (AuthSecretUse.signIn, signIn),
      'deleting the account': (
        AuthSecretUse.reconfirm,
        () => AuthService.deleteAccount(password: _password),
      ),
      "a drive's role": (
        AuthSecretUse.reconfirm,
        () => StorageService.setDeviceRole(
          serial: 'S1',
          role: 'default-storage',
          username: 'grace',
          password: _password,
        ),
      ),
      'a snapshot backup': (
        AuthSecretUse.reconfirm,
        () => StorageService.startSnapshotBackup(
          targetDeviceSerial: 'S1',
          username: 'grace',
          password: _password,
        ),
      ),
      "the vault's storage location": (
        AuthSecretUse.reconfirm,
        () => VaultService.setStorageLocation(
          targetDeviceSerial: 'S1',
          username: 'grace',
          password: _password,
        ),
      ),
      'setup': (
        AuthSecretUse.newCredential,
        () => AuthService.setup(username: 'grace', password: _password),
      ),
      'an account request': (
        AuthSecretUse.newCredential,
        () =>
            AuthService.requestAccount(username: 'grace', password: _password),
      ),
      'an admin creating one': (
        AuthSecretUse.newCredential,
        () => UsersService.create(username: 'grace', password: _password),
      ),
      'a recovery': (
        AuthSecretUse.newCredential,
        () => AuthService.recover(
          username: 'grace',
          recoveryPhrase: 'a-b-c',
          newPassword: _password,
        ),
      ),
    };

    for (final MapEntry(key: name, value: (use, call)) in flows.entries) {
      for (final (why, status, body, missing) in [
        ('a 404', 404, null, false),
        ('the 401 an older Quark gives an unknown API path', 401, null, false),
        ('the web fallback page', 200, '<!DOCTYPE html><html></html>', false),
        ('no legacyRecovery', 200, null, true),
      ]) {
        test('$name, on a Quark with $why: update the Quark', () async {
          quark
            ..saltStatus = status
            ..saltBody = body;
          if (missing) quark.legacyRecovery = null;

          await expectLater(call(), refusesWith(Errors.quarkTooOld));
          expect(quark.sent, isEmpty);
        });
      }

      if (use == AuthSecretUse.reconfirm) {
        test('$name, for an account with no auth key: sign in again', () async {
          quark.legacy = true;

          await expectLater(call(), refusesWith(Errors.accountTooOld));
          expect(quark.sent, isEmpty);
        });
      }
    }

    test('a new credential for a username the Quark marks legacy is still '
        'set: the Quark decides whether the name is taken', () async {
      quark.legacy = true;

      await UsersService.create(username: 'grace', password: _password);

      expect(quark.lastBody, {'username': 'grace', 'authKey': authKey});
    });
  });

  group('the one-time upgrade of a legacy account', () {
    test(
      'sends the password beside the key once, then the key alone',
      () async {
        quark.legacy = true;

        await signIn();
        expect(quark.lastBody, {
          'username': 'grace',
          'password': _password,
          'authKey': authKey,
        });

        await signIn();
        expect(quark.lastBody, {'username': 'grace', 'authKey': authKey});
        // The password went out in exactly one request.
        expect(
          quark.requests.where((r) => r.body.contains(_password)),
          hasLength(1),
        );
      },
    );

    test('a later legacy claim from a Quark the account signed in to with '
        'its key still gets the upgrade, as a reset Quark needs', () async {
      await signIn();
      expect(quark.lastBody, {'username': 'grace', 'authKey': authKey});
      quark.legacy = true;

      await signIn();

      expect(quark.lastBody, {
        'username': 'grace',
        'password': _password,
        'authKey': authKey,
      });
    });
  });

  group('the one legacy-phrase recovery', () {
    late List<Map<String, dynamic>> fetches;

    setUp(() {
      quark.legacyRecovery = true;
      fetches = [];
      chatKeysForRecovery =
          ({
            required username,
            required recoveryPhrase,
            recoveryKeys,
            newPhraseWrapKey,
            required newPassword,
            required authSalt,
          }) async {
            fetches.add({
              'recoveryKeys': recoveryKeys != null,
              'newPhraseWrapKey': newPhraseWrapKey != null,
            });
            return WrappedChatKeys(
              publicKeys: ChatPublicKeys(
                boxPublicKey: Uint8List(32),
                signPublicKey: Uint8List(32),
              ),
              byPassword: WrappedSecret(
                wrapped: Uint8List(104),
                salt: authSalt,
              ),
              byPhrase: null,
              kdfParams: KdfParams.standard.split,
            );
          };
    });
    tearDown(
      () => chatKeysForRecovery = ChatKeysController.instance.keysForRecovery,
    );

    Future<LoginResult> recover() => AuthService.recover(
      username: 'grace',
      recoveryPhrase: 'old-quark-phrase',
      newPassword: _password,
    );

    test('sends the phrase once beside both new keys, and returns the new '
        'phrase', () async {
      final result = await recover();

      final phrase = result.recoveryPhrase!;
      expect(phrase.split('-'), hasLength(6));
      expect(quark.lastBody.keys, {
        'username',
        'recoveryPhrase',
        'newAuthKey',
        'newRecoveryKey',
        'chatKeys',
      });
      expect(quark.lastBody['recoveryPhrase'], 'old-quark-phrase');
      expect(quark.lastBody['newAuthKey'], authKey);
      expect(quark.lastBody['newRecoveryKey'], await testRecoveryKey(phrase));
      expect(quark.lastBody.toString(), isNot(contains(phrase)));
      expect(fetches, [
        {'recoveryKeys': false, 'newPhraseWrapKey': true},
      ]);
      expect(settings.sessionToken, 'session');
    });

    test('an account with a recovery key is sent only the key', () async {
      quark.legacyRecovery = false;

      final result = await recover();

      expect(result.recoveryPhrase, isNull);
      expect(quark.lastBody.keys, {
        'username',
        'recoveryKey',
        'newAuthKey',
        'chatKeys',
      });
      expect(fetches, [
        {'recoveryKeys': true, 'newPhraseWrapKey': false},
      ]);
      expect(quark.lastBody.toString(), isNot(contains('old-quark-phrase')));
    });
  });

  group('a new account is given its auth key, not its password:', () {
    // #2430: with the recovery key of a phrase the app generated, so the
    // Quark makes none and never sees the one shown.
    test('setup', () async {
      final result = await AuthService.setup(
        username: 'grace',
        password: _password,
      );

      expect(quark.sent.single.url.path, '/api/v0/auth/setup');
      expect(quark.lastBody, {
        'username': 'grace',
        'authKey': authKey,
        'recoveryKey': await testRecoveryKey(result.recoveryPhrase),
      });
      expect(result.recoveryPhrase.split('-'), hasLength(6));
      expect(quark.sent.single.body, isNot(contains(result.recoveryPhrase)));
      expect(quark.sent.single.body, isNot(contains(_password)));
      await pumpEventQueue();
      expect(chatSalts, [testAuthSalt]);
      // The chat keys' phrase wrap is under the generated phrase's key.
      expect(chatPhrases, ['key']);
    });

    test('an account request', () async {
      final phrase = await AuthService.requestAccount(
        username: 'grace',
        password: _password,
      );

      expect(quark.sent.single.url.path, '/api/v0/auth/request-account');
      expect(quark.lastBody, {
        'username': 'grace',
        'authKey': authKey,
        'recoveryKey': await testRecoveryKey(phrase),
      });
      expect(phrase.split('-'), hasLength(6));
      expect(quark.sent.single.body, isNot(contains(phrase)));
    });

    test('an admin creating one', () async {
      await settings.setSessionToken('session');

      await UsersService.create(username: 'grace', password: _password);

      expect(quark.sent.single.url.path, '/api/v0/admin/users');
      expect(quark.lastBody, {'username': 'grace', 'authKey': authKey});
      // The salt was asked for the new account, not the admin.
      expect(quark.requests.first.url.queryParameters, {'username': 'grace'});
    });
  });

  group('a re-confirmation sends the auth key in the password field:', () {
    setUp(() async {
      await settings.setSessionToken('session');
      await settings.setUsername('grace');
    });

    Future<void> expectAuthKey(
      String path,
      Future<void> Function() call,
    ) async {
      await call();
      expect(quark.sent.single.url.path, path);
      expect(quark.lastBody['password'], authKey);
      expect(quark.sent.single.body, isNot(contains(_password)));
    }

    test(
      'deleting the account',
      () => expectAuthKey(
        '/api/v0/auth/account',
        () => AuthService.deleteAccount(password: _password),
      ),
    );

    test(
      "a drive's role",
      () => expectAuthKey(
        '/api/v0/storage/devices/role',
        () => StorageService.setDeviceRole(
          serial: 'S1',
          role: 'default-storage',
          username: 'grace',
          password: _password,
        ),
      ),
    );

    test(
      'a snapshot backup',
      () => expectAuthKey(
        '/api/v0/storage/devices/snapshot-backup',
        () => StorageService.startSnapshotBackup(
          targetDeviceSerial: 'S1',
          username: 'grace',
          password: _password,
        ),
      ),
    );

    test('a snapshot backup with no username sends no password', () async {
      await StorageService.startSnapshotBackup(
        targetDeviceSerial: 'S1',
        password: _password,
      );

      expect(quark.lastBody, {'targetDeviceSerial': 'S1'});
    });

    test(
      "the vault's storage location",
      () => expectAuthKey(
        '/api/v0/vault/storage-location',
        () => VaultService.setStorageLocation(
          targetDeviceSerial: 'S1',
          username: 'grace',
          password: _password,
        ),
      ),
    );
  });
}

List<int>? _tryBase64(String value) {
  try {
    return base64Decode(value);
  } on FormatException {
    return null;
  }
}

/// Every string inside decoded JSON, at any depth, and each nested object as
/// it was encoded.
Iterable<String> _strings(Object? json) sync* {
  if (json is String) {
    yield json;
  } else if (json is Map) {
    yield jsonEncode(json);
    for (final value in json.values) {
      yield* _strings(value);
    }
  } else if (json is List) {
    for (final value in json) {
      yield* _strings(value);
    }
  } else if (json != null) {
    yield '$json';
  }
}
