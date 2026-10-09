import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/controllers/vault_restore_controller.dart';
import 'package:quark/pages/vault_page.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/services/vault_backup_service.dart';
import 'package:quark/services/vault_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/vault/restore/vault_restore_dialog.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/text_scale.dart';

StorageDevice _drive(String serial) => StorageDevice(
  name: 'Drive $serial',
  devicePath: '/dev/sda1',
  mountPoint: '/mnt/usb',
  fileSystem: 'ext4',
  totalBytes: 2048,
  usedBytes: 1024,
  availableBytes: 1024,
  isInternal: false,
  isEnabled: true,
  serial: serial,
);

/// #1665: the restore-from-backup-drive dialog, and its way in from the vault
/// page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final password = find.byKey(const ValueKey('vault_restore_password'));
  final submit = find.byKey(const ValueKey('vault_restore_submit'));
  final cancel = find.byKey(const ValueKey('vault_restore_cancel'));
  final done = find.byKey(const ValueKey('vault_restore_done'));
  final summary = find.byKey(const ValueKey('vault_restore_summary'));

  bool enabled(WidgetTester tester) =>
      tester.widget<FilledButton>(submit).onPressed != null;

  /// Taps [target], scrolling it into view first: the dialog scrolls its own
  /// content on a narrow viewport.
  Future<void> tapVisible(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
  }

  /// Opens the dialog over a page at [size], with fakes for the Quark.
  Future<void> open(
    WidgetTester tester, {
    Size size = wideViewport,
    List<StorageDevice> devices = const [],
    Future<VaultRestoreResult> Function()? restore,
    List<(String, String)>? calls,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => VaultRestoreDialog(
                  controller: VaultRestoreController(
                    listDevices: () async => devices,
                    restoreFromDrive:
                        ({
                          required deviceSerial,
                          required recoveryPassword,
                        }) async {
                          calls?.add((deviceSerial, recoveryPassword));
                          return restore == null
                              ? const VaultRestoreResult()
                              : restore();
                        },
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';

    testWidgets('restores from the picked drive and reports it ($label)', (
      tester,
    ) async {
      final calls = <(String, String)>[];
      await open(
        tester,
        size: size,
        devices: [_drive('A'), _drive('B')],
        calls: calls,
        restore: () async =>
            const VaultRestoreResult(entriesImported: 3, entriesSkipped: 2),
      );
      expect(tester.takeException(), isNull);
      expect(enabled(tester), isFalse, reason: 'no drive, no password');

      await tapVisible(
        tester,
        find.byKey(const ValueKey('vault_restore_device_B')),
      );
      await tester.pump();
      expect(enabled(tester), isFalse, reason: 'no password yet');

      await tester.enterText(password, 'recovery words');
      await tester.pump();
      expect(tester.widget<TextField>(password).obscureText, isTrue);
      expect(enabled(tester), isTrue);

      await tapVisible(tester, submit);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(calls, [('B', 'recovery words')]);
      expect(summary, findsOneWidget);
      expect(find.text('Restored 3 entries.'), findsOneWidget);
      expect(password, findsNothing);

      await tapVisible(tester, done);
      await tester.pumpAndSettle();
      expect(find.byType(VaultRestoreDialog), findsNothing);
    });

    testWidgets('a rejected backup shows the copy and stays open ($label)', (
      tester,
    ) async {
      await open(
        tester,
        size: size,
        devices: [_drive('A')],
        restore: () async => throw const ApiException(400),
      );
      await tester.enterText(password, 'wrong');
      await tester.pump();
      await tapVisible(tester, submit);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(Errors.vaultBackupRejected), findsOneWidget);
      expect(summary, findsNothing);
      expect(enabled(tester), isTrue, reason: 'the user can try again');
    });

    testWidgets('with no drive, says so and cannot restore ($label)', (
      tester,
    ) async {
      await open(tester, size: size);
      await tester.enterText(password, 'recovery words');
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('No backup drive found'), findsOneWidget);
      expect(enabled(tester), isFalse);

      await tapVisible(tester, cancel);
      await tester.pumpAndSettle();
      expect(find.byType(VaultRestoreDialog), findsNothing);
    });
  }

  testWidgets('shows progress and locks the form while restoring', (
    tester,
  ) async {
    final gate = Completer<VaultRestoreResult>();
    await open(tester, devices: [_drive('A')], restore: () => gate.future);
    await tester.enterText(password, 'recovery words');
    await tester.pump();
    await tapVisible(tester, submit);
    await tester.pump();

    expect(enabled(tester), isFalse);
    expect(tester.widget<TextField>(password).enabled, isFalse);
    expect(
      find.descendant(of: submit, matching: find.byType(QuarkLoader)),
      findsOneWidget,
    );

    gate.complete(const VaultRestoreResult(entriesImported: 1));
    await tester.pumpAndSettle();
    expect(summary, findsOneWidget);
  });

  testWidgets('closes when the vault locked itself first', (tester) async {
    await open(
      tester,
      devices: [_drive('A')],
      restore: () async => throw VaultLockedException(),
    );
    await tester.enterText(password, 'recovery words');
    await tester.pump();
    await tapVisible(tester, submit);
    await tester.pumpAndSettle();

    expect(find.byType(VaultRestoreDialog), findsNothing);
  });

  group('from the vault page', () {
    final requests = <http.Request>[];

    /// Serves an unlocked vault with one backup drive plugged in.
    void serve() {
      requests.clear();
      StorageService.invalidateDeviceCache();
      resetSharedHttpClient();
      sharedHttpClientFactory = () => MockClient((request) async {
        requests.add(request);
        final Object? body = switch (request.url.path) {
          '/api/v0/vault/status' => {'initialized': true, 'locked': false},
          '/api/v0/vault/entries' => {'entries': <Object>[]},
          '/api/v0/vault/folders' => {'folders': <Object>[]},
          '/api/v0/storage/devices/status' => {
            'devices': [
              {
                'name': 'Backup',
                'mountPoint': '/mnt/usb',
                'isEnabled': true,
                'usbInfo': {'serial': 'SN123'},
              },
            ],
          },
          '/api/v0/vault/import-backup' => {
            'entriesImported': 2,
            'entriesSkipped': 1,
          },
          _ => null,
        };
        return body == null
            ? http.Response('', 404)
            : http.Response(jsonEncode(body), 200);
      });
    }

    tearDown(() {
      StorageService.invalidateDeviceCache();
      resetSharedHttpClient();
      sharedHttpClientFactory = buildLocalTrustHttpClient;
    });

    int count(String path) => requests.where((r) => r.url.path == path).length;

    testWidgets('the overflow menu opens it, and the vault reloads after', (
      tester,
    ) async {
      serve();
      tester.view.physicalSize = wideViewport;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
          home: const VaultPage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('vault_more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vault_restore_backup')));
      await tester.pumpAndSettle();
      expect(find.byType(VaultRestoreDialog), findsOneWidget);

      await tester.enterText(password, 'recovery words');
      await tester.pump();
      await tapVisible(tester, submit);
      await tester.pumpAndSettle();

      final sent = requests.singleWhere(
        (r) => r.url.path == '/api/v0/vault/import-backup',
      );
      expect(jsonDecode(sent.body), {
        'deviceSerial': 'SN123',
        'recoveryPassword': 'recovery words',
      });
      expect(find.text('Restored 2 entries.'), findsOneWidget);

      final listed = count('/api/v0/vault/entries');
      await tapVisible(tester, done);
      await tester.pumpAndSettle();
      expect(find.byType(VaultRestoreDialog), findsNothing);
      expect(count('/api/v0/vault/entries'), listed + 1);
    });
  });
}
