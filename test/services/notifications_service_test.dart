import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/models/app_notification.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/notifications_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #2493: the notifications list, and the per-type switch saved in the
/// account's own settings.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final settings = AppSettings.instance;
  final requests = <http.Request>[];

  /// Answers each request with what [respond] returns for it, recording it.
  void answerWith(http.Response Function(http.Request request) respond) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      return respond(request);
    });
  }

  /// Answers every request with [status] and [body], recording it.
  void answer(int status, Object body) =>
      answerWith((_) => http.Response(jsonEncode(body), status));

  /// Serves `/settings/me` from [stored] the way the Quark does: a GET reads
  /// it and a PUT replaces it whole.
  void serveSettings(Map<String, dynamic> stored) => answerWith((request) {
    if (request.method == 'PUT') {
      stored
        ..clear()
        ..addAll(jsonDecode(request.body) as Map<String, dynamic>);
    }
    return http.Response(jsonEncode(stored), 200);
  });

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  setUp(() async {
    requests.clear();
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'One', 'hostAddress': 'http://one.local'},
      ]),
    });
    await settings.load();
    await settings.setSessionToken('token');
  });
  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  group('list', () {
    test('reads the notifications with the session', () async {
      answer(200, {
        'notifications': [
          {
            'type': 'backup_stale',
            'link': '/system/storage',
            'lastBackupAt': '2026-09-01T10:00:00Z',
          },
        ],
      });
      final notifications = await NotificationsService.list();
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/api/v0/notifications');
      expect(requests.single.headers['Authorization'], 'Bearer token');
      expect(notifications.single.type, NotificationType.backupStale);
      expect(notifications.single.link, '/system/storage');
      expect(notifications.single.lastBackupAt, DateTime.utc(2026, 9, 1, 10));
    });

    test('an account with none reads an empty list', () async {
      answer(200, {'notifications': <Object>[]});
      expect(await NotificationsService.list(), isEmpty);
    });

    test('leaves out a type this app does not know', () async {
      answer(200, {
        'notifications': [
          {'type': 'calendar_reminder', 'link': '/calendar'},
          {'type': 'backup_due', 'link': '/system/storage'},
        ],
      });
      final notifications = await NotificationsService.list();
      expect(notifications.single.type, NotificationType.backupDue);
    });

    test('a refusal is an ApiException carrying the status', () async {
      answer(500, {'error': 'boom'});
      await expectLater(
        NotificationsService.list(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('a body without a notifications list is a FormatException', () async {
      answer(200, {'items': <Object>[]});
      await expectLater(
        NotificationsService.list(),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('disabledTypes', () {
    test('reads disabledNotifications from the account settings', () async {
      answer(200, {
        'themeColor': '',
        'disabledNotifications': ['backup_due'],
      });
      expect(await NotificationsService.disabledTypes(), {'backup_due'});
      expect(requests.single.url.path, '/api/v0/settings/me');
    });

    test('is empty when the Quark leaves the field out', () async {
      answer(200, {'themeColor': 'violet'});
      expect(await NotificationsService.disabledTypes(), isEmpty);
    });
  });

  group('setEnabled', () {
    test('turning a type off keeps the theme color', () async {
      final stored = <String, dynamic>{'themeColor': 'violet'};
      serveSettings(stored);
      final disabled = await NotificationsService.setEnabled(
        NotificationType.backupDue,
        false,
      );
      expect(disabled, {'backup_due'});
      expect(requests.map((r) => r.method), ['GET', 'PUT']);
      expect(requests.last.url.path, '/api/v0/settings/me');
      expect(jsonDecode(requests.last.body), {
        'themeColor': 'violet',
        'disabledNotifications': ['backup_due'],
      });
    });

    test('turning a type on keeps the other types off', () async {
      final stored = <String, dynamic>{
        'themeColor': '',
        'disabledNotifications': ['backup_due', 'backup_stale', 'newer_type'],
      };
      serveSettings(stored);
      final disabled = await NotificationsService.setEnabled(
        NotificationType.backupDue,
        true,
      );
      expect(disabled, {'backup_stale', 'newer_type'});
      expect(jsonDecode(requests.last.body), {
        'themeColor': '',
        'disabledNotifications': ['backup_stale', 'newer_type'],
      });
    });

    test('turning off a type that is already off lists it once', () async {
      final stored = <String, dynamic>{
        'disabledNotifications': ['backup_due'],
      };
      serveSettings(stored);
      await NotificationsService.setEnabled(NotificationType.backupDue, false);
      expect(jsonDecode(requests.last.body), {
        'disabledNotifications': ['backup_due'],
      });
    });

    test('a refused save is an ApiException', () async {
      answerWith(
        (request) => request.method == 'GET'
            ? http.Response('{}', 200)
            : http.Response(jsonEncode({'error': 'unknown type'}), 400),
      );
      await expectLater(
        NotificationsService.setEnabled(NotificationType.backupDue, false),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });
  });
}
