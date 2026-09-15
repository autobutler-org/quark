import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A Quark that answers every request with one canned response, and remembers
/// what it was asked.
class _RecordingClient extends http.BaseClient {
  _RecordingClient({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
  final requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request as http.Request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      statusCode,
      request: request,
    );
  }
}

/// #1908: requesting an account, and a sign-in refused for the account's
/// status rather than its password.
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

  final settings = AppSettings.instance;

  setUp(() async {
    stored.clear();
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'One', 'hostAddress': 'http://one.local'},
      ]),
      'activeHostIndex': 0,
    });
    await settings.load();
  });

  tearDown(() => authHttpClientFactory = () => sharedHttpClient);

  _RecordingClient serve(int statusCode, Object body) {
    final client = _RecordingClient(
      statusCode: statusCode,
      body: jsonEncode(body),
    );
    authHttpClientFactory = () => client;
    return client;
  }

  Matcher refusedWith(String sentence) => throwsA(
    isA<MessageException>().having((e) => e.message, 'message', sentence),
  );

  group('signing in', () {
    for (final (status, sentence) in [
      ('pending', Errors.accountPending),
      ('disabled', Errors.accountDisabled),
    ]) {
      test('a $status account is told why, and gets no session', () async {
        serve(403, {'error': 'refused', 'status': status});

        await expectLater(
          AuthService.login(username: 'bob', password: 'hunter2hunter2'),
          refusedWith(sentence),
        );
        expect(settings.sessionToken, isNull);
      });
    }

    test('a wrong password is still the credentials sentence', () async {
      serve(401, {'error': 'invalid credentials'});

      await expectLater(
        AuthService.login(username: 'bob', password: 'nope'),
        refusedWith('Invalid username or password.'),
      );
    });
  });

  test('recovering a disabled account is told why', () async {
    serve(403, {'error': 'refused', 'status': 'disabled'});

    await expectLater(
      AuthService.recover(
        username: 'bob',
        recoveryPhrase: 'a b c',
        newPassword: 'hunter2hunter2',
      ),
      refusedWith(Errors.accountDisabled),
    );
    expect(settings.sessionToken, isNull);
  });

  group('requesting an account', () {
    test('sends the request and returns the recovery phrase', () async {
      final client = serve(201, {'recoveryPhrase': 'apple banana cherry'});

      final phrase = await AuthService.requestAccount(
        username: 'bob',
        password: 'hunter2hunter2',
      );

      expect(phrase, 'apple banana cherry');
      final request = client.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v0/auth/request-account');
      expect(jsonDecode(request.body), {
        'username': 'bob',
        'password': 'hunter2hunter2',
      });
      // An admin approves the account before it can sign in.
      expect(settings.sessionToken, isNull);
    });

    test('a Quark not taking requests says so', () async {
      serve(404, {'error': "this Quark isn't taking account requests"});

      await expectLater(
        AuthService.requestAccount(username: 'bob', password: 'hunter2hunter2'),
        refusedWith(Errors.accessRequestsOff),
      );
    });

    test("a taken username passes the Quark's text on", () async {
      serve(409, {'error': 'that username is taken'});

      await expectLater(
        AuthService.requestAccount(username: 'bob', password: 'hunter2hunter2'),
        refusedWith('that username is taken'),
      );
    });
  });

  test('the status reports whether requests are taken', () async {
    serve(200, {'setup': true, 'accessRequestsEnabled': true});
    expect((await AuthService.checkStatus()).accessRequestsEnabled, isTrue);

    serve(200, {'setup': false});
    expect((await AuthService.checkStatus()).accessRequestsEnabled, isFalse);
  });
}
