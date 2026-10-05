import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/controllers/chat_keys_controller.dart';
import 'package:quark/models/chat_keys.dart';
import 'package:quark/services/app_settings.dart';
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

/// A Quark that records every request it is sent, answers the salt endpoint
/// as configured, and gives a legacy account its auth key when a sign-in
/// carries both credentials.
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
  bool? legacyRecovery;

  /// The phrase a sign-in hands back, as an admin-created account's first
  /// one does.
  String? serverPhrase;

  /// What `PUT /auth/recovery-key` answers.
  int rotationStatus = 204;

  /// The account's stored chat keys, as `/chat/keys/me` keeps them.
  Map<String, dynamic>? chatKeys;

  /// Whether a sign-in carrying both credentials stores the auth key.
  bool upgrades = true;

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
        if (sent.containsKey('password') &&
            sent.containsKey('authKey') &&
            upgrades) {
          legacy = false;
        }
        return http.Response(
          jsonEncode({
            'token': 'session',
            'recoveryPhrase': ?serverPhrase,
            'legacyRecovery': ?legacyRecovery,
          }),
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
      // A Quark that took the recovery key makes no phrase.
      case '/api/v0/auth/setup':
        return http.Response(
          jsonEncode({
            'token': 'session',
            if (!sent.containsKey('recoveryKey')) 'recoveryPhrase': 'a-b-c',
          }),
          200,
        );
      case '/api/v0/auth/request-account':
        return http.Response(
          jsonEncode({
            if (!sent.containsKey('recoveryKey')) 'recoveryPhrase': 'a-b-c',
          }),
          201,
        );
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

/// #2430: the app sends a key derived from the password, never the password,
/// and nothing it sends opens the chat keys.
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

  /// What each [chatKeysOnSignIn] was handed for the phrase wrap: the
  /// Quark's phrase, `key` for a generated phrase's wrap key, or null.
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
          recoveryPhrase,
          phraseWrapKey,
          required sessionToken,
          authSalt,
        }) async {
          chatSalts.add(authSalt);
          chatPhrases.add(phraseWrapKey == null ? recoveryPhrase : 'key');
          return null;
        };
  });

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
    authHttpClientFactory = () => sharedHttpClient;
  });

  Matcher refusesTheDowngrade() => throwsA(
    isA<MessageException>().having(
      (e) => e.message,
      'message',
      Errors.passwordDowngradeRefused,
    ),
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
        ({
          required password,
          recoveryPhrase,
          phraseWrapKey,
          required sessionToken,
          authSalt,
        }) => keysController
            .signedIn(
              password: password,
              recoveryPhrase: recoveryPhrase,
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
        ({
          required password,
          recoveryPhrase,
          phraseWrapKey,
          required sessionToken,
          authSalt,
        }) => keysController.signedIn(
          password: password,
          recoveryPhrase: recoveryPhrase,
          phraseWrapKey: phraseWrapKey,
          sessionToken: sessionToken,
          authSalt: authSalt,
        );
    chatKeysForRecovery = keysController.keysForRecovery;
    addTearDown(
      () => chatKeysForRecovery = ChatKeysController.instance.keysForRecovery,
    );
    const serverPhrase = 'abandon-ability-able-about-above-absent';
    const second = 'second password, after a recovery';
    const third = 'third password, after another';

    // An account whose phrase the Quark made, chat keys wrapped under it.
    quark.legacyRecovery = true;
    await keysController.signedIn(
      password: _password,
      recoveryPhrase: serverPhrase,
      sessionToken: 'session',
      authSalt: testAuthSalt,
    );
    quark.requests.clear();

    // 1. A legacy recovery, which has to send that phrase, gives a new one.
    final first = await AuthService.recover(
      username: 'grace',
      recoveryPhrase: serverPhrase,
      newPassword: second,
    );
    final p1 = first.recoveryPhrase!;
    await pumpEventQueue();
    // 2. A recovery with that one sends only its key.
    expect(
      (await AuthService.recover(
        username: 'grace',
        recoveryPhrase: p1,
        newPassword: third,
      )).recoveryPhrase,
      isNull,
    );
    await pumpEventQueue();
    final p1Keys = WrappedChatKeys.fromJson(quark.chatKeys!);
    // 3. A sign-in the Quark says has no recovery key rotates it.
    quark.legacyRecovery = true;
    final p2 = (await AuthService.login(
      username: 'grace',
      password: third,
    )).recoveryPhrase!;
    final p2Keys = WrappedChatKeys.fromJson(quark.chatKeys!);

    Map<String, dynamic> body(String path, bool Function(Map) where) => quark
        .sent
        .where((r) => r.url.path == path)
        .map((r) => jsonDecode(r.body) as Map<String, dynamic>)
        .singleWhere(where);
    final p1Key = await testRecoveryKey(p1);
    final p2Key = await testRecoveryKey(p2);
    final thirdKey = await testAuthKey(third);
    expect(
      body('/api/v0/auth/recover', (b) => b.containsKey('recoveryPhrase')),
      containsPair('newRecoveryKey', p1Key),
    );
    expect(
      body('/api/v0/auth/recover/keys', (b) => b.containsKey('recoveryKey')),
      {'username': 'grace', 'recoveryKey': p1Key},
    );
    expect(
      body('/api/v0/auth/recover', (b) => b.containsKey('recoveryKey')),
      containsPair('recoveryKey', p1Key),
    );
    final rotation = body('/api/v0/auth/recovery-key', (_) => true);
    expect(rotation['password'], thirdKey);
    expect(rotation['recoveryKey'], p2Key);
    expect(rotation['chatKeys'], quark.chatKeys);
    expect(p2Keys.kdfParams.alg, KdfParams.phraseSplitAlgorithm);
    expect(settings.hasRecoveryKey('grace'), isTrue);

    // Neither generated phrase nor any password ever went out. The Quark's
    // own phrase did, once: the legacy recovery cannot avoid it.
    for (final request in quark.requests) {
      final all = '${request.url} ${request.headers} ${request.body}';
      for (final secret in [p1, p2, _password, second, third]) {
        expect(all, isNot(contains(secret)), reason: request.url.path);
      }
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
    expect(seen, containsAll([p1Key, p2Key, thirdKey, serverPhrase]));
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
    final mine = crypto.deriveAuthKeys(third, testAuthSalt, params);
    addTearDown(mine.dispose);
    expect(
      crypto.unwrapWithKey(p2Keys.byPassword, mine.wrapKey).box.publicKey,
      box,
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  group('rotating at sign-in (#2430)', () {
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
      expect(chatPhrases, ['key']);
      // Held for the phrase step, as a first sign-in is.
      expect(settings.sessionToken, isNull);
      expect(settings.hasRecoveryKey('grace'), isTrue);
    });

    test('a refused one returns nothing, keeps the session, and is tried '
        'again at the next sign-in', () async {
      quark.rotationStatus = 403;

      final result = await signIn();

      expect(result.recoveryPhrase, isNull);
      expect(settings.sessionToken, 'session');
      expect(settings.hasRecoveryKey('grace'), isFalse);

      quark.rotationStatus = 204;
      expect((await signIn()).recoveryPhrase, isNotNull);
      expect(rotations(), hasLength(2));
    });

    test("an admin-created account's first sign-in shows the app's phrase, "
        "never the Quark's", () async {
      quark.serverPhrase = 'server-made-phrase';

      final result = await signIn();

      expect(result.recoveryPhrase, isNot('server-made-phrase'));
      expect(result.recoveryPhrase, isNotNull);
      // Nor are the chat keys wrapped under it.
      expect(chatPhrases, ['key']);

      quark
        ..requests.clear()
        ..rotationStatus = 403
        ..legacyRecovery = true;
      expect((await signIn()).recoveryPhrase, isNull);
    });

    test('a legacy password account rotates with its auth key', () async {
      quark.legacy = true;

      await signIn();

      expect(jsonDecode(rotations().single.body)['password'], authKey);
      expect(rotations().single.body, isNot(contains(_password)));
    });

    test('a Quark that does not report recovery keys gets no rotation, and '
        'its phrase is the one shown', () async {
      quark
        ..legacyRecovery = null
        ..serverPhrase = 'server-made-phrase';

      final result = await signIn();

      expect(rotations(), isEmpty);
      expect(result.recoveryPhrase, 'server-made-phrase');
      await pumpEventQueue();
      expect(chatPhrases, ['server-made-phrase']);
    });
  });

  group('signing in', () {
    test('asks for the salt by the exact username, then sends the auth '
        'key', () async {
      await AuthService.login(username: 'Grace', password: _password);

      expect(quark.requests.first.url.queryParameters, {'username': 'Grace'});
      expect(quark.lastBody, {'username': 'Grace', 'authKey': authKey});
      expect(settings.signsInWithAuthKey('Grace'), isTrue);
      expect(settings.signsInWithAuthKey('grace'), isFalse);
      await pumpEventQueue();
      expect(chatSalts, [testAuthSalt]);
    });

    test('a legacy account is upgraded with both credentials, once', () async {
      quark.legacy = true;

      await signIn();
      expect(quark.lastBody, {
        'username': 'grace',
        'password': _password,
        'authKey': authKey,
      });
      expect(settings.signsInWithAuthKey('grace'), isTrue);

      await signIn();
      expect(quark.sent, hasLength(2));
      expect(quark.lastBody, {'username': 'grace', 'authKey': authKey});
    });

    test('an upgrade the Quark did not store is not remembered', () async {
      quark
        ..legacy = true
        ..upgrades = false;

      await signIn();
      expect(settings.signsInWithAuthKey('grace'), isFalse);

      await signIn();
      expect(quark.lastBody, containsPair('password', _password));
    });

    for (final (name, status, body) in [
      ('a 404', 404, null),
      ('the 401 an older Quark gives an unknown API path', 401, null),
      ('the web fallback page', 200, '<!DOCTYPE html><html></html>'),
    ]) {
      test('a Quark with no salt endpoint ($name) gets the password, with '
          'nothing remembered', () async {
        quark
          ..saltStatus = status
          ..saltBody = body;

        await signIn();

        expect(quark.lastBody, {'username': 'grace', 'password': _password});
        expect(settings.signsInWithAuthKey('grace'), isFalse);
        await pumpEventQueue();
        // The chat keys stay in the first scheme.
        expect(chatSalts, [null]);
      });
    }

    test(
      'a failing salt endpoint fails the sign-in and sends nothing',
      () async {
        quark.saltStatus = 500;

        await expectLater(signIn(), throwsA(isA<ApiException>()));
        expect(quark.sent, isEmpty);
      },
    );
  });

  group('once an account has signed in with its auth key', () {
    setUp(() async {
      await signIn();
      expect(settings.signsInWithAuthKey('grace'), isTrue);
      quark.requests.clear();
    });

    void claim(String what) {
      switch (what) {
        case 'legacy':
          quark.legacy = true;
        case '404':
          quark.saltStatus = 404;
        case '401':
          quark.saltStatus = 401;
        default:
          quark.saltBody = '<!DOCTYPE html><html></html>';
      }
    }

    for (final what in ['legacy', '404', '401', 'no salt in a 200']) {
      test('a Quark claiming $what is refused the password', () async {
        claim(what);

        await expectLater(signIn(), refusesTheDowngrade());
        await expectLater(
          AuthService.deleteAccount(password: _password),
          refusesTheDowngrade(),
        );

        expect(quark.sent, isEmpty);
        for (final request in quark.requests) {
          expect(request.url.toString(), isNot(contains(_password)));
        }
      });
    }

    test('the refusal is per Quark and per account', () async {
      claim('404');

      await AuthService.login(username: 'ada', password: _password);
      expect(quark.lastBody, {'username': 'ada', 'password': _password});

      await settings.setActiveIndex(1);
      await signIn();
      expect(quark.lastBody, {'username': 'grace', 'password': _password});
    });

    test('it survives a restart', () async {
      await settings.load();
      claim('legacy');

      await expectLater(signIn(), refusesTheDowngrade());
    });

    test('a recovery still sets a new auth key on a legacy claim', () async {
      claim('legacy');
      chatKeysForRecovery =
          ({
            required username,
            required recoveryPhrase,
            recoveryKeys,
            newPhraseWrapKey,
            required newPassword,
            authSalt,
          }) async => WrappedChatKeys(
            publicKeys: ChatPublicKeys(
              boxPublicKey: Uint8List(32),
              signPublicKey: Uint8List(32),
            ),
            byPassword: WrappedSecret(wrapped: Uint8List(104), salt: authSalt!),
            byPhrase: null,
            kdfParams: KdfParams.standard.split,
          );
      addTearDown(
        () => chatKeysForRecovery = ChatKeysController.instance.keysForRecovery,
      );

      await AuthService.recover(
        username: 'grace',
        recoveryPhrase: 'a-b-c',
        newPassword: _password,
      );

      expect(quark.lastBody['newAuthKey'], authKey);
      expect(quark.lastBody.containsKey('newPassword'), isFalse);
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
      expect(settings.signsInWithAuthKey('grace'), isTrue);
      expect(settings.hasRecoveryKey('grace'), isTrue);
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
    });

    test('an admin creating one', () async {
      await settings.setSessionToken('session');

      await UsersService.create(username: 'grace', password: _password);

      expect(quark.sent.single.url.path, '/api/v0/admin/users');
      expect(quark.lastBody, {'username': 'grace', 'authKey': authKey});
      // The salt was asked for the new account, not the admin.
      expect(quark.requests.first.url.queryParameters, {'username': 'grace'});
    });

    test('a Quark with no salt endpoint is still sent the password, and its '
        'phrase is the one shown', () async {
      quark.saltStatus = 404;

      final result = await AuthService.setup(
        username: 'grace',
        password: _password,
      );

      expect(quark.lastBody, {'username': 'grace', 'password': _password});
      expect(result.recoveryPhrase, 'a-b-c');
      expect(settings.hasRecoveryKey('grace'), isFalse);
      await pumpEventQueue();
      expect(chatPhrases, ['a-b-c']);
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

      // An account with no auth key yet can only be checked by its password.
      quark
        ..requests.clear()
        ..legacy = true;
      await call();
      expect(quark.lastBody['password'], _password);
    }

    test(
      'deleting the account',
      () => expectAuthKey('/api/v0/auth/account', () async {
        await AuthService.deleteAccount(password: _password);
        // A deletion signs the app out; the next call needs its session.
        await settings.setSessionToken('session');
        await settings.setUsername('grace');
      }),
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
