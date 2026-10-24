// cspell:words reallocated celsius
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/storage_devices/credentials_dialog.dart';
import 'package:quark/widgets/system/storage_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/auth_salt.dart';
import '../../support/secure_storage.dart';

/// Drive health on the Storage tab: the verdict the Quark sent, the stronger
/// warning when default storage would move to a worse drive, and the
/// acknowledgment a Replace soon drive requires.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sent = <http.Request>[];

  Map<String, Object?> drive({
    required String verdict,
    String reason = 'This spinning drive is heavily used.',
    bool worseThanDefault = false,
    String role = 'unassigned',
    bool backup = false,
  }) {
    return {
      'name': 'Stick',
      'devicePath': '/dev/sdb1',
      'mountPoint': '/mnt/stick',
      'fileSystem': 'ext4',
      'isInternal': false,
      'isEnabled': true,
      'role': role,
      'usbInfo': {'serial': 'USB1'},
      'health': {
        'verdict': verdict,
        'reason': reason,
        'smartStatus': 'failed',
        'reallocatedSectors': 12,
        'pendingSectors': 3,
        'powerOnHours': 60000,
        'temperatureCelsius': 41,
        'media': 'spinning',
        'linkSpeed': 'USB 2.0',
        'worseThanDefault': worseThanDefault,
      },
      'diskProbe': {'speedClass': 'slow'},
    };
  }

  setUpAll(() async {
    // Complete libsodium outside the tester's fake clock. A load that finishes
    // inside pump's zone leaves the next test waiting on that future forever.
    await ChatCrypto.load();
    mockSecureStorage();
  });

  setUp(() async {
    sent.clear();
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
  });

  tearDown(() {
    AppSettings.instance.isAdmin.value = false;
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
    authHttpClientFactory = () => sharedHttpClient;
  });

  void serve(Map<String, Object?> deviceJson) {
    sharedHttpClientFactory = () => AuthSaltClient(
      MockClient((request) async {
        sent.add(request);
        final path = request.url.path;
        if (path == '/api/v0/storage/devices/status') {
          return http.Response(
            jsonEncode({
              'devices': [deviceJson],
            }),
            200,
          );
        }
        if (path == '/api/v0/storage/devices/role') {
          return http.Response(
            jsonEncode({'serial': 'USB1', 'role': 'default-storage'}),
            200,
          );
        }
        if (path == '/api/v0/storage/devices/snapshot-backup') {
          return http.Response(jsonEncode({'jobId': 'job-1'}), 200);
        }
        return http.Response(jsonEncode({'error': ''}), 404);
      }),
    );
  }

  Future<void> pumpTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StorageTab())),
    );
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'grace');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    // The role or backup request derives its auth key on the real event loop.
    await pumpWhileDeriving(tester);
  }

  testWidgets('shows each reading the Quark sent, and no manufacture year', (
    tester,
  ) async {
    serve(
      drive(
        verdict: 'replace-soon',
        reason: 'This spinning drive is heavily used.',
      ),
    );
    await pumpTab(tester);

    expect(find.text('Replace soon'), findsOneWidget);
    expect(find.text('Healthy'), findsNothing);
    expect(find.text('This spinning drive is heavily used.'), findsOneWidget);

    await tester.tap(find.text('Show details'));
    await tester.pumpAndSettle();

    expect(find.text('failed'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('60000 hours'), findsOneWidget);
    expect(find.text('41°C'), findsOneWidget);
    expect(find.text('Spinning'), findsOneWidget);
    expect(find.text('USB 2.0'), findsOneWidget);
    expect(find.text('Slow'), findsOneWidget);
    expect(find.textContaining('year'), findsNothing);
    expect(find.textContaining('manufacture'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown shows the Quark sentence and never Healthy', (
    tester,
  ) async {
    serve(
      drive(verdict: 'unknown', reason: 'The health tool is not installed.'),
    );
    await pumpTab(tester);

    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('Healthy'), findsNothing);
    expect(find.text('The health tool is not installed.'), findsOneWidget);
  });

  testWidgets('a non-admin sees the verdict and no drive actions', (
    tester,
  ) async {
    AppSettings.instance.isAdmin.value = false;
    serve(drive(verdict: 'watch'));
    await pumpTab(tester);

    expect(find.text('Watch'), findsOneWidget);
    expect(find.text('This spinning drive is heavily used.'), findsOneWidget);
    expect(find.text('Set Role'), findsNothing);
    expect(find.text('Back Up'), findsNothing);
  });

  testWidgets(
    'replace soon default storage warns and sends the acknowledgment',
    (tester) async {
      serve(drive(verdict: 'replace-soon', worseThanDefault: true));
      await pumpTab(tester);

      await tester.tap(find.text('Set Role'));
      await tester.pumpAndSettle();
      expect(find.text('Replace soon'), findsWidgets);
      await tester.tap(find.text('Default Storage'));
      await tester.pumpAndSettle();

      expect(find.text('This drive is in worse shape'), findsOneWidget);
      expect(
        find.text(
          'This drive is in worse health than the current default storage.',
        ),
        findsOneWidget,
      );
      expect(find.text('Files already on this drive stay.'), findsOneWidget);
      expect(find.text('Use this drive anyway'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(sent.where((r) => r.url.path.endsWith('/role')), isEmpty);

      await tester.tap(find.text('Set Role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Default Storage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this drive anyway'));
      await tester.pumpAndSettle();
      expect(find.byType(CredentialsDialog), findsOneWidget);
      await signIn(tester);

      final role = sent.where((r) => r.url.path.endsWith('/role'));
      expect(role, hasLength(1));
      expect(jsonDecode(role.single.body)['acknowledgeHealth'], isTrue);
    },
  );

  testWidgets('watch does not block a backup role', (tester) async {
    serve(drive(verdict: 'watch', worseThanDefault: true));
    await pumpTab(tester);

    await tester.tap(find.text('Set Role'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snapshot Backup'));
    await tester.pumpAndSettle();

    expect(find.text('Use this drive anyway'), findsNothing);
    expect(find.text('This drive is in worse shape'), findsNothing);
    expect(find.byType(CredentialsDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(sent.where((r) => r.url.path.endsWith('/role')), isEmpty);
  });

  testWidgets('watch on a worse drive warns before becoming default storage', (
    tester,
  ) async {
    serve(drive(verdict: 'watch', worseThanDefault: true));
    await pumpTab(tester);

    await tester.tap(find.text('Set Role'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Default Storage'));
    await tester.pumpAndSettle();

    expect(find.text('This drive is in worse shape'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Use this drive anyway'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('drive_health_ack_USB1_confirm')),
    );
    await tester.pumpAndSettle();
    await signIn(tester);

    final role = sent.where((r) => r.url.path.endsWith('/role'));
    expect(role, hasLength(1));
    expect(
      jsonDecode(role.single.body).containsKey('acknowledgeHealth'),
      isFalse,
    );
  });

  testWidgets('starting a backup on replace soon sends the acknowledgment', (
    tester,
  ) async {
    serve(drive(verdict: 'replace-soon', role: 'snapshot-backup'));
    await pumpTab(tester);

    await tester.tap(find.text('Back Up'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Files already on this drive stay. The backup is added beside them.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Use this drive anyway'));
    await tester.pumpAndSettle();
    // A backup asks for no password (#3460): the confirmation is next.
    await tester.tap(find.widgetWithText(TextButton, 'Start Backup'));
    await tester.pumpAndSettle();

    final backup = sent.where(
      (r) => r.method == 'POST' && r.url.path.endsWith('/snapshot-backup'),
    );
    expect(backup, hasLength(1));
    expect(jsonDecode(backup.single.body)['acknowledgeHealth'], isTrue);
  });
}
