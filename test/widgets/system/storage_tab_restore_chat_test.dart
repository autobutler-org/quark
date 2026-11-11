import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/controllers/restore_chat_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/system/storage_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/secure_storage.dart';
import '../../support/tap_target_guidelines.dart' show setViewport;

/// An admin restores the chat from the snapshot-backup drive (#2428). The
/// Quark is a fake on the controller, so the test never derives a password.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <(String, String)>[];

  setUpAll(mockSecureStorage);

  setUp(() async {
    calls.clear();
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'Home', 'hostAddress': 'http://quark.local'},
      ]),
      'activeHostIndex': 0,
    });
    await AppSettings.instance.load();
    AppSettings.instance.isAdmin.value = true;
    StorageService.invalidateDeviceCache();
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      if (request.url.path == '/api/v0/storage/devices/status') {
        return http.Response(
          jsonEncode({
            'devices': [
              {
                'name': 'Backups',
                'usbInfo': {'serial': 'USB2'},
                'mountPoint': '/mnt/backups',
                'role': 'snapshot-backup',
                'isEnabled': true,
              },
            ],
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'error': ''}), 404);
    });
  });

  tearDown(() {
    AppSettings.instance.isAdmin.value = false;
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  RestoreChatController controller({Object? error, ChatRestoreResult? result}) {
    final restore = RestoreChatController(
      restoreChat:
          ({
            required String deviceSerial,
            required String password,
            String? run,
          }) async {
            calls.add((deviceSerial, password));
            if (error != null) throw error;
            return result ??
                const ChatRestoreResult(
                  channels: 3,
                  messages: 12,
                  unmatchedUsers: ['carol'],
                );
          },
    );
    addTearDown(restore.dispose);
    return restore;
  }

  Future<void> pumpTab(
    WidgetTester tester,
    RestoreChatController restore,
  ) async {
    setViewport(tester, const Size(1280, 800));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StorageTab(restoreChat: restore)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester, String password) async {
    await tester.tap(
      find.byKey(const ValueKey('device_card_restore_chat_USB2')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('restore_chat_password')),
      password,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('restore_chat_confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets('an admin sees Restore chat and a non-admin does not', (
    tester,
  ) async {
    await pumpTab(tester, controller());
    expect(find.text('Restore chat'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('device_card_restore_chat_USB2')),
      findsOneWidget,
    );

    AppSettings.instance.isAdmin.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Restore chat'), findsNothing);
  });

  testWidgets(
    'the dialog says it replaces an empty chat and to create the accounts '
    'first, and Cancel sends nothing',
    (tester) async {
      await pumpTab(tester, controller());
      await tester.tap(
        find.byKey(const ValueKey('device_card_restore_chat_USB2')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Restore chat from this drive'), findsOneWidget);
      expect(
        find.text(
          'The restore replaces an empty chat. If chat already has messages '
          'or channels, it is refused and nothing changes.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'The backup does not carry accounts. Each person is matched by '
          'username, so create their accounts first.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('restore_chat_cancel')));
      await tester.pumpAndSettle();

      expect(calls, isEmpty);
      expect(find.text('Restore chat from this drive'), findsNothing);
    },
  );

  testWidgets('confirm restores that drive with the typed password', (
    tester,
  ) async {
    await pumpTab(tester, controller());

    await confirm(tester, 'secret');

    expect(calls, [('USB2', 'secret')]);
  });

  testWidgets('a successful restore shows the counts and unmatched names', (
    tester,
  ) async {
    await pumpTab(tester, controller());

    await confirm(tester, 'secret');

    expect(
      find.text(
        'Restored 3 channels and 12 messages. No account here matched these '
        'usernames, so their messages show no author: carol.',
      ),
      findsOneWidget,
    );
  });

  for (final (name, error, shown) in <(String, Object, String)>[
    (
      'a chat that is not empty',
      const MessageException('chat already has channels or messages'),
      'Chat already has channels or messages.',
    ),
    ('a drive with no backups', const ApiException(404), Errors.noBackupsYet),
  ]) {
    testWidgets('$name shows the message', (tester) async {
      await pumpTab(tester, controller(error: error));

      await confirm(tester, 'secret');

      expect(find.text(shown), findsOneWidget);
    });
  }
}
