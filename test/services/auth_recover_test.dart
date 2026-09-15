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
    });
    expect(AppSettings.instance.sessionToken, 'new-token');
    // Recovery now names the account, so the app knows who is signed in.
    expect(AppSettings.instance.username, 'grace');
  });
}
