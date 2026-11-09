import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/storage_devices/credentials_dialog.dart';
import 'package:quark/widgets/storage_devices/eject_drive_dialog.dart';
import 'package:quark/widgets/storage_devices/snapshot_backup_dialog.dart';
import 'package:quark/widgets/system/storage_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/secure_storage.dart';
import '../../support/tap_target_guidelines.dart' show setViewport;

/// The Storage tab's dialogs: the credentials dialog owns its text
/// controllers, so closing it and letting it animate out never rebuilds a
/// field with a disposed controller (#3102), a snapshot backup asks for
/// no password at all (#3460), and Eject asks before it unmounts (#1664).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The body of the last snapshot backup the tab started.
  Object? backupBody;

  /// The method and path of every unmount the tab sent.
  final ejectRequests = <String>[];

  setUpAll(mockSecureStorage);

  setUp(() async {
    backupBody = null;
    ejectRequests.clear();
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
              {
                'name': 'Built-in storage',
                'isInternal': true,
                'mountPoint': '/',
                'role': 'unassigned',
                'isEnabled': true,
              },
              {
                'name': 'Photos',
                'usbInfo': {'serial': 'USB3'},
                'mountPoint': '/mnt/photos',
                'role': 'default-storage',
                'isEnabled': true,
              },
              {
                'name': 'Unplugged',
                'usbInfo': {'serial': 'USB4'},
                'mountPoint': '',
                'role': 'unassigned',
                'isEnabled': false,
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/api/v0/storage/devices/usb/USB2') {
        ejectRequests.add('${request.method} ${request.url.path}');
        return http.Response(jsonEncode({'message': 'ok'}), 200);
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
    setViewport(tester, const Size(1280, 800));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StorageTab())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(button).first);
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
    await openFromCard(tester, 'Back up onto this drive');

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

  testWidgets('the dialog names the data drives it copies onto the target', (
    tester,
  ) async {
    await openFromCard(tester, 'Back up onto this drive');

    expect(find.text('Choose the drives to copy onto Backups.'), findsOne);
    // The backup drive and an unplugged drive are not offered.
    expect(
      find.descendant(
        of: find.byType(SnapshotBackupDialog),
        matching: find.byType(CheckboxListTile),
      ),
      findsNWidgets(2),
    );
    expect(find.byKey(const ValueKey('backup_source_')), findsOne);
    expect(find.byKey(const ValueKey('backup_source_USB3')), findsOne);

    await closeWith(tester, 'Cancel');
  });

  testWidgets('Start Backup with every drive sends the target and nothing '
      'else', (tester) async {
    await openFromCard(tester, 'Back up onto this drive');

    await closeWith(tester, 'Start Backup');

    // No sourceSerials: a drive attached later is still copied (#3984).
    expect(backupBody, {'targetDeviceSerial': 'USB2'});
    // Unmounts the tab, which stops its status poll.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Start Backup sends only the drives left checked', (
    tester,
  ) async {
    await openFromCard(tester, 'Back up onto this drive');
    await tester.tap(find.byKey(const ValueKey('backup_source_USB3')));
    await tester.pump();

    await closeWith(tester, 'Start Backup');

    expect(backupBody, {
      'targetDeviceSerial': 'USB2',
      'sourceSerials': [''],
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Eject asks first, then unmounts the drive', (tester) async {
    await openFromCard(tester, 'Eject');
    expect(find.byType(EjectDriveDialog), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('eject_dialog_confirm')));
    await tester.pumpAndSettle();

    expect(ejectRequests, ['DELETE /api/v0/storage/devices/usb/USB2']);
    expect(find.text('Backups is safe to unplug'), findsOneWidget);
  });

  testWidgets('canceling Eject sends nothing', (tester) async {
    await openFromCard(tester, 'Eject');

    await closeWith(tester, 'Cancel');

    expect(find.byType(EjectDriveDialog), findsNothing);
    expect(ejectRequests, isEmpty);
  });
}
