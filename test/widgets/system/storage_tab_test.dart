import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/storage_devices/credentials_dialog.dart';
import 'package:quark/widgets/storage_devices/snapshot_backup_dialog.dart';
import 'package:quark/widgets/system/storage_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/secure_storage.dart';

/// The Storage tab's dialogs: the credentials dialog owns its text
/// controllers, so closing it and letting it animate out never rebuilds a
/// field with a disposed controller (#3102), and a snapshot backup asks for
/// no password at all (#3460).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The body of the last snapshot backup the tab started.
  Object? backupBody;

  setUpAll(mockSecureStorage);

  setUp(() async {
    backupBody = null;
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
      if (request.url.path == '/api/v0/storage/devices/snapshot-backup') {
        backupBody = jsonDecode(request.body);
        return http.Response(jsonEncode({'jobId': '7'}), 202);
      }
      return http.Response(jsonEncode({'error': ''}), 404);
    });
  });

  tearDown(() {
    AppSettings.instance.isAdmin.value = false;
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  /// Pumps the tab and taps [button] on the drive's card.
  Future<void> openFromCard(WidgetTester tester, String button) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StorageTab())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();
  }

  /// Taps [label] and pumps the dialog's exit animation frame by frame, which
  /// is where a field rebuilding with a disposed controller would throw.
  Future<void> closeWith(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('the credentials dialog closes without a disposed controller', (
    tester,
  ) async {
    await openFromCard(tester, 'Set Role');
    await tester.tap(find.text('Unassigned'));
    await tester.pumpAndSettle();
    expect(find.byType(CredentialsDialog), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'grace');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'pw');

    await closeWith(tester, 'Cancel');

    expect(find.byType(CredentialsDialog), findsNothing);
  });

  testWidgets('a snapshot backup asks for no password', (tester) async {
    await openFromCard(tester, 'Back Up');

    expect(find.byType(CredentialsDialog), findsNothing);
    expect(find.byType(SnapshotBackupDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SnapshotBackupDialog),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );

    await closeWith(tester, 'Cancel');

    expect(find.byType(SnapshotBackupDialog), findsNothing);
    expect(backupBody, isNull);
  });

  testWidgets('Start Backup sends the target and nothing else', (tester) async {
    await openFromCard(tester, 'Back Up');

    await closeWith(tester, 'Start Backup');

    expect(backupBody, {'targetDeviceSerial': 'USB2'});
    // Unmounts the tab, which stops its status poll.
    await tester.pumpWidget(const SizedBox());
  });
}
