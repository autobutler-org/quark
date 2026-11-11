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

/// `POST /storage/devices/snapshot-backup/restore-chat` sends the drive, the
/// run and the admin's auth key, and a 4xx `error` string is the message the
/// page shows (#2428).
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

  test(
    'sends the serial, the run and the auth key of the login password',
    () async {
      respond = () => http.Response(
        jsonEncode({
          'channels': 3,
          'messages': 12,
          'unmatchedUsers': ['carol'],
          'run': '2026-11-02 09.00',
        }),
        200,
      );

      final result = await StorageService.restoreSnapshotChat(
        deviceSerial: 'USB2',
        password: _password,
        run: '2026-11-02 09.00',
      );

      final posted = requests.single;
      expect(posted.method, 'POST');
      expect(
        posted.url.path,
        '/api/v0/storage/devices/snapshot-backup/restore-chat',
      );
      expect(jsonDecode(posted.body), {
        'deviceSerial': 'USB2',
        'password': await testAuthKey(_password),
        'run': '2026-11-02 09.00',
      });
      expect(result.channels, 3);
      expect(result.messages, 12);
      expect(result.unmatchedUsers, ['carol']);
      expect(result.run, '2026-11-02 09.00');
    },
  );

  test('a 409 error string is a message, not a status', () async {
    respond = () => http.Response(
      jsonEncode({'error': 'chat already has channels or messages'}),
      409,
    );

    await expectLater(
      StorageService.restoreSnapshotChat(
        deviceSerial: 'USB2',
        password: _password,
      ),
      throwsA(
        isA<MessageException>().having(
          (e) => e.message,
          'message',
          'chat already has channels or messages',
        ),
      ),
    );
  });

  test('a 404 for the newest backup is a status the page explains', () async {
    respond = () => http.Response(
      jsonEncode({'error': 'the drive holds no snapshot'}),
      404,
    );

    await expectLater(
      StorageService.restoreSnapshotChat(
        deviceSerial: 'USB2',
        password: _password,
      ),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
    );
  });
}
