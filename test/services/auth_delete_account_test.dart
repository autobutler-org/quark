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
  _RecordingClient({this.statusCode = 200, this.body = '{"deleted":{}}'});

  final int statusCode;
  final String body;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      statusCode,
      request: request,
    );
  }
}

/// #1762: the app has to be able to delete an account from inside itself, and
/// only the account. The endpoint can also factory-reset the appliance, so
/// what this call does and does not select is the contract worth pinning.
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
        {'name': 'Two', 'hostAddress': 'http://two.local'},
      ]),
      'activeHostIndex': 0,
    });
    await settings.load();
    await settings.setSessionToken('one-token');
    await settings.setUsername('ada');
    await settings.setActiveIndex(1);
    await settings.setSessionToken('two-token');
    await settings.setUsername('grace');
    await settings.setActiveIndex(0);
  });

  tearDown(() => authHttpClientFactory = () => sharedHttpClient);

  _RecordingClient serve({int statusCode = 200, String body = '{}'}) {
    final client = _RecordingClient(statusCode: statusCode, body: body);
    authHttpClientFactory = () => client;
    return client;
  }

  test('deleting an account selects the account and nothing else', () async {
    final client = serve();

    await AuthService.deleteAccount(confirmUsername: 'ada');

    final request = client.requests.single;
    expect(request.method, 'DELETE');
    expect(request.url.path, '/api/v0/auth/account');
    // Not "account plus some false flags": the appliance-wide aspects are not
    // this call's to send, so they are not in it at all.
    expect(request.url.queryParameters, {'account': 'true', 'confirm': 'ada'});
    expect(request.headers['Authorization'], 'Bearer one-token');
  });

  test('resetting selects the appliance and never the account', () async {
    final client = serve();

    await AuthService.resetQuark(
      confirmUsername: 'ada',
      database: true,
      files: true,
      devices: false,
    );

    expect(client.requests.single.url.queryParameters, {
      'database': 'true',
      'files': 'true',
      'devices': 'false',
      'confirm': 'ada',
    });
  });

  test('reaching an attached drive is sent only when asked for', () async {
    final client = serve();

    await AuthService.resetQuark(
      confirmUsername: 'ada',
      database: false,
      files: true,
      devices: true,
    );

    final query = client.requests.single.url.queryParameters;
    expect(query['devices'], 'true');
    expect(query['database'], 'false');
  });

  test('reports the files the Quark says it kept', () async {
    serve(body: '{"deleted":{"account":true},"filesRetained":true}');

    final result = await AuthService.deleteAccount(confirmUsername: 'ada');

    expect(result.filesRetained, isTrue);
  });

  test('claims nothing about files when the Quark did not say', () async {
    serve(body: '{"deleted":{"account":true}}');

    final result = await AuthService.deleteAccount(confirmUsername: 'ada');

    expect(result.filesRetained, isFalse);
  });

  test('forgets the session on this Quark only', () async {
    serve();

    await AuthService.deleteAccount(confirmUsername: 'ada');

    expect(settings.sessionTokenFor('http://one.local'), isNull);
    expect(settings.usernameFor('http://one.local'), isNull);
    expect(settings.sessionTokenFor('http://two.local'), 'two-token');
    expect(settings.usernameFor('http://two.local'), 'grace');
  });

  test('keeps the session when the Quark refuses the confirmation', () async {
    serve(
      statusCode: 400,
      body: '{"error":"confirm must be the authenticated username"}',
    );

    await expectLater(
      AuthService.deleteAccount(confirmUsername: 'nope'),
      throwsA(isA<MessageException>()),
    );
    expect(settings.sessionToken, 'one-token');
  });

  test('a dead session is a sign-out, not a failed deletion', () async {
    serve(statusCode: 401, body: '{"error":"not authenticated"}');

    await expectLater(
      AuthService.deleteAccount(confirmUsername: 'ada'),
      throwsA(isA<UnauthorizedException>()),
    );
    expect(settings.sessionToken, isNull);
  });
}
