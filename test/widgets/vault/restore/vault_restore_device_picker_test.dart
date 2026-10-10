import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/vault/restore/vault_restore_device_picker.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/text_scale.dart';

StorageDevice _drive(String serial, {String name = ''}) => StorageDevice(
  name: name,
  devicePath: '/dev/sda1',
  mountPoint: '/mnt/usb',
  fileSystem: 'ext4',
  totalBytes: 2048,
  usedBytes: 1024,
  availableBytes: 1024,
  isInternal: false,
  isEnabled: true,
  model: 'Model $serial',
  serial: serial,
);

/// #1665: the drive picker of the restore-from-backup-drive dialog.
void main() {
  final retry = find.byKey(const ValueKey('vault_restore_devices_retry'));

  Future<void> pump(
    WidgetTester tester,
    Size size, {
    List<StorageDevice> devices = const [],
    String? selectedSerial,
    bool isLoading = false,
    String? error,
    ValueChanged<String>? onSelect,
    VoidCallback? onRetry,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: Scaffold(
          body: VaultRestoreDevicePicker(
            devices: devices,
            selectedSerial: selectedSerial,
            isLoading: isLoading,
            error: error,
            onSelect: onSelect ?? (_) {},
            onRetry: onRetry ?? () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';

    testWidgets('lists the drives and reports a pick ($label)', (tester) async {
      final picked = <String>[];
      await pump(
        tester,
        size,
        devices: [
          _drive('A', name: 'A very long drive name that has to wrap ' * 3),
          _drive('B'),
        ],
        selectedSerial: 'A',
        onSelect: picked.add,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Model B'), findsOneWidget, reason: 'unnamed drive');
      expect(find.text('1.0 KB / 2.0 KB'), findsNWidgets(2));
      expect(retry, findsNothing);

      await tester.tap(find.byKey(const ValueKey('vault_restore_device_B')));
      expect(picked, ['B']);
    });

    testWidgets('says so when no drive is found ($label)', (tester) async {
      var retries = 0;
      await pump(tester, size, onRetry: () => retries++);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('No backup drive found'), findsOneWidget);
      await tester.tap(retry);
      expect(retries, 1);
    });

    testWidgets('shows a failed listing with a retry ($label)', (tester) async {
      await pump(
        tester,
        size,
        devices: [_drive('A')],
        error: "Couldn't load your drives.",
      );

      expect(tester.takeException(), isNull);
      expect(find.text("Couldn't load your drives."), findsOneWidget);
      expect(retry, findsOneWidget);
      expect(find.byType(RadioListTile<String>), findsNothing);
    });

    testWidgets('shows a loader while listing ($label)', (tester) async {
      await pump(tester, size, isLoading: true);

      expect(tester.takeException(), isNull);
      expect(find.byType(QuarkLoader), findsOneWidget);
      expect(retry, findsNothing);
    });
  }
}
