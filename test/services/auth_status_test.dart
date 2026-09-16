import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A Quark that answers every request with one canned response, and remembers
/// what it was asked.
class _RecordingClient extends http.BaseClient {
  _RecordingClient({this.statusCode = 200, required this.body});

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

/// #1898: the app learns whether the signed-in user is an admin from
/// GET /auth/status, and keeps it where the router and drawer can read it.
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
    settings.isAdmin.value = false;
  });

  tearDown(() => authHttpClientFactory = () => sharedHttpClient);

  _RecordingClient serve(String body, {int statusCode = 200}) {
    final client = _RecordingClient(statusCode: statusCode, body: body);
    authHttpClientFactory = () => client;
    return client;
  }

  test('an admin session is reported as admin', () async {
    await settings.setSessionToken('admin-token');
    final client = serve('{"setup":true,"username":"ada","isAdmin":true}');

    await AuthService.refreshAccount();

    expect(
      client.requests.single.headers['Authorization'],
      'Bearer admin-token',
    );
    expect(settings.isAdmin.value, isTrue);
    expect(settings.username, 'ada');
  });

  test('a demoted admin loses the flag on the next refresh', () async {
    await settings.setSessionToken('admin-token');
    serve('{"setup":true,"username":"ada","isAdmin":true}');
    await AuthService.refreshAccount();
    expect(settings.isAdmin.value, isTrue);

    serve('{"setup":true,"username":"ada","isAdmin":false}');
    await AuthService.refreshAccount();

    expect(settings.isAdmin.value, isFalse);
  });

  test('without a session there is no admin and no request', () async {
    settings.isAdmin.value = true;
    final client = serve('{"setup":true}');

    await AuthService.refreshAccount();

    expect(settings.isAdmin.value, isFalse);
    expect(client.requests, isEmpty);
  });

  test('an anonymous status call sends no credentials', () async {
    final client = serve('{"setup":true}');

    final status = await AuthService.checkStatus();

    expect(
      client.requests.single.headers.containsKey('Authorization'),
      isFalse,
    );
    expect(status.setupComplete, isTrue);
    expect(status.username, isNull);
    expect(status.isAdmin, isFalse);
  });
}
