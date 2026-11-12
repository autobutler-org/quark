import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/controllers/restore_vault_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/system/storage_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/secure_storage.dart';
import '../../support/tap_target_guidelines.dart' show setViewport;

const _missingAccount =
    'the backup has a vault for an account this Quark does not have; add an '
    'account with the same username, letter for letter, and restore again '
    '(carol, dave)';

const _keyExists =
    'an account the backup has a vault for already has a vault on this Quark, '
    'and a restore never replaces one; that account can delete its empty '
    'vault, then restore again (carol)';

/// An admin restores vaults from the snapshot-backup drive. The Quark is a
/// fake on the controller, so the test never derives a password.
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

  RestoreVaultController controller({
    Object? error,
    VaultRestoreResult? result,
  }) {
    final restore = RestoreVaultController(
      restoreVault:
          ({
            required String deviceSerial,
            required String password,
            String? run,
          }) async {
            calls.add((deviceSerial, password));
            if (error != null) throw error;
            return result ??
                const VaultRestoreResult(
                  accounts: 2,
                  items: 5,
                  backupPasswordAccounts: ['alice', 'bob'],
                );
          },
    );
    addTearDown(restore.dispose);
    return restore;
  }

  Future<void> pumpTab(
    WidgetTester tester,
    RestoreVaultController restore,
  ) async {
    setViewport(tester, const Size(1280, 800));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StorageTab(restoreVault: restore)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester, String password) async {
    await tester.tap(find.byKey(const ValueKey('device_card_restore_USB2')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('restore_vault_password')),
      password,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('restore_vault_confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets('an admin sees Restore vaults and a non-admin does not', (
    tester,
  ) async {
    await pumpTab(tester, controller());
    expect(find.text('Restore vaults'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('device_card_restore_USB2')),
      findsOneWidget,
    );

    AppSettings.instance.isAdmin.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Restore vaults'), findsNothing);
  });

  testWidgets(
    'the dialog states the three warnings, and Cancel sends nothing',
    (tester) async {
      await pumpTab(tester, controller());
      await tester.tap(find.byKey(const ValueKey('device_card_restore_USB2')));
      await tester.pumpAndSettle();

      expect(find.text('Restore vaults from this drive'), findsOneWidget);
      expect(
        find.text(
          'Each vault goes to the account with exactly the same username. '
          'Carol is not carol.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Every vault in the backup must have its account here first, or '
          'nothing is restored.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'After a move to new hardware, each person unlocks their vault '
          'with the password they had when the backup was taken.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('restore_vault_cancel')));
      await tester.pumpAndSettle();

      expect(calls, isEmpty);
      expect(find.text('Restore vaults from this drive'), findsNothing);
    },
  );

  testWidgets('confirm restores that drive with the typed password', (
    tester,
  ) async {
    await pumpTab(tester, controller());

    await confirm(tester, 'secret');

    expect(calls, [('USB2', 'secret')]);
  });

  testWidgets('a successful restore shows the summary', (tester) async {
    await pumpTab(tester, controller());

    await confirm(tester, 'secret');

    expect(
      find.text(
        'Restored 2 vaults and 5 entries. alice and bob unlock with the '
        'password they had when the backup was taken.',
      ),
      findsOneWidget,
    );
  });

  for (final (name, error, shown) in <(String, Object, String)>[
    (
      'items already stored',
      const MessageException('a vault already has items'),
      'A vault already has items.',
    ),
    (
      'a missing account',
      const MessageException(_missingAccount),
      'The backup has a vault for an account this Quark does not have; add '
          'an account with the same username, letter for letter, and restore '
          'again (carol, dave).',
    ),
    (
      'a vault key that already exists',
      const MessageException(_keyExists),
      'An account the backup has a vault for already has a vault on this '
          'Quark, and a restore never replaces one; that account can delete '
          'its empty vault, then restore again (carol).',
    ),
    ('a drive with no backups', const ApiException(404), Errors.noBackupsYet),
    (
      'no vault backup',
      const MessageException('the drive holds no vault backup'),
      'The drive holds no vault backup.',
    ),
  ]) {
    testWidgets('$name shows the message', (tester) async {
      await pumpTab(tester, controller(error: error));

      await confirm(tester, 'secret');

      expect(find.text(shown), findsOneWidget);
    });
  }
}
