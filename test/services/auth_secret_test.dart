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

  /// Whether a sign-in carrying both credentials stores the auth key.
  bool upgrades = true;

  late final http.Client client = MockClient((request) async {
    final path = request.url.path;
    if (path == '/api/v0/auth/salt') {
      requests.add(request);
      final body =
          saltBody ??
          jsonEncode({'salt': base64Encode(testAuthSalt), 'legacy': legacy});
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
        return http.Response('{"token":"session"}', 200);
      case '/api/v0/auth/recover':
        return http.Response('{"token":"session"}', 200);
      case '/api/v0/auth/setup':
        return http.Response(
          '{"token":"session","recoveryPhrase":"a-b-c"}',
          200,
        );
      case '/api/v0/auth/request-account':
        return http.Response('{"recoveryPhrase":"a-b-c"}', 201);
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
    chatKeysOnSignIn =
        ({
          required password,
          recoveryPhrase,
          required sessionToken,
          authSalt,
        }) async => chatSalts.add(authSalt);
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

  Future<void> signIn() =>
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
          required sessionToken,
          authSalt,
        }) => keysController
            .signedIn(
              password: password,
              recoveryPhrase: recoveryPhrase,
              sessionToken: sessionToken,
              authSalt: authSalt,
            )
            .then(unlocked.complete, onError: unlocked.completeError);

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
    test('setup', () async {
      await AuthService.setup(username: 'grace', password: _password);

      expect(quark.sent.single.url.path, '/api/v0/auth/setup');
      expect(quark.lastBody, {'username': 'grace', 'authKey': authKey});
      expect(settings.signsInWithAuthKey('grace'), isTrue);
      await pumpEventQueue();
      expect(chatSalts, [testAuthSalt]);
    });

    test('an account request', () async {
      await AuthService.requestAccount(username: 'grace', password: _password);

      expect(quark.sent.single.url.path, '/api/v0/auth/request-account');
      expect(quark.lastBody, {'username': 'grace', 'authKey': authKey});
    });

    test('an admin creating one', () async {
      await settings.setSessionToken('session');

      await UsersService.create(username: 'grace', password: _password);

      expect(quark.sent.single.url.path, '/api/v0/admin/users');
      expect(quark.lastBody, {'username': 'grace', 'authKey': authKey});
      // The salt was asked for the new account, not the admin.
      expect(quark.requests.first.url.queryParameters, {'username': 'grace'});
    });

    test('a Quark with no salt endpoint is still sent the password', () async {
      quark.saltStatus = 404;

      await AuthService.setup(username: 'grace', password: _password);

      expect(quark.lastBody, {'username': 'grace', 'password': _password});
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
