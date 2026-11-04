import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/auth_salt.dart';
import '../support/secure_storage.dart';

const _password = 'correct horse battery staple';

/// `POST /storage/devices/snapshot-backup/restore-vault` sends the drive and
/// the admin's auth key, and a 4xx `error` string is the message the page shows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <http.Request>[];
  late http.Response Function() respond;

  setUpAll(mockSecureStorage);

  setUp(() async {
    requests.clear();
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'Home', 'hostAddress': 'http://quark.local'},
      ]),
      'activeHostIndex': 0,
    });
    await AppSettings.instance.load();
    await AppSettings.instance.setUsername('ada');
    resetSharedHttpClient();
    sharedHttpClientFactory = () => AuthSaltClient(
      MockClient((request) async {
        requests.add(request);
        return respond();
      }),
    );
  });

  tearDown(() async {
    await AppSettings.instance.setUsername(null);
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  test('sends the serial and the auth key of the login password', () async {
    respond = () => http.Response(
      jsonEncode({
        'accounts': 1,
        'items': 2,
        'backupPasswordAccounts': ['ada'],
        'restoredAccounts': ['ada'],
      }),
      200,
    );

    final result = await StorageService.restoreSnapshotVault(
      deviceSerial: 'USB2',
      password: _password,
    );

    final posted = requests.single;
    expect(posted.method, 'POST');
    expect(
      posted.url.path,
      '/api/v0/storage/devices/snapshot-backup/restore-vault',
    );
    expect(jsonDecode(posted.body), {
      'deviceSerial': 'USB2',
      'password': await testAuthKey(_password),
    });
    expect(result.accounts, 1);
    expect(result.items, 2);
    expect(result.backupPasswordAccounts, ['ada']);
    expect(result.restoredAccounts, ['ada']);
  });

  test('a 409 error string is a message, not a status', () async {
    respond = () =>
        http.Response(jsonEncode({'error': 'a vault already has items'}), 409);

    await expectLater(
      StorageService.restoreSnapshotVault(
        deviceSerial: 'USB2',
        password: _password,
      ),
      throwsA(
        isA<MessageException>().having(
          (e) => e.message,
          'message',
          'a vault already has items',
        ),
      ),
    );
  });
}
