import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/storage_devices/device_card.dart';

/// #1664: a plugged-in drive offers Eject, which a running backup or an eject
/// already in flight disables, and an unmounted one says it is safe to unplug.
void main() {
  StorageDevice drive({
    bool isInternal = false,
    String mountPoint = '/mnt/usb',
    bool isEnabled = true,
  }) => StorageDevice(
    name: 'Stick',
    devicePath: '/dev/sdb1',
    mountPoint: mountPoint,
    fileSystem: 'ext4',
    totalBytes: 0,
    usedBytes: 0,
    availableBytes: 0,
    isInternal: isInternal,
    isEnabled: isEnabled,
    serial: isInternal ? '' : 'USB1',
  );

  Future<void> pumpCard(
    WidgetTester tester,
    StorageDevice device, {
    VoidCallback? onEject,
    bool isEjecting = false,
    bool isBackupRunning = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DeviceCard(
          device: device,
          isMounting: false,
          onEject: onEject,
          isEjecting: isEjecting,
          isBackupRunning: isBackupRunning,
        ),
      ),
    ),
  );

  const ejectKey = ValueKey('device_card_eject_USB1');

  ButtonStyleButton eject(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(find.byKey(ejectKey));

  testWidgets('an enabled USB drive offers Eject', (tester) async {
    var ejected = 0;
    await pumpCard(tester, drive(), onEject: () => ejected++);

    await tester.tap(find.byKey(ejectKey));

    expect(ejected, 1);
  });

  testWidgets('no Eject without a callback or on built-in storage', (
    tester,
  ) async {
    await pumpCard(tester, drive());
    expect(find.text('Eject'), findsNothing);

    await pumpCard(tester, drive(isInternal: true), onEject: () {});
    expect(find.text('Eject'), findsNothing);
  });

  testWidgets('Eject is disabled while a backup runs', (tester) async {
    await pumpCard(tester, drive(), onEject: () {}, isBackupRunning: true);

    expect(eject(tester).onPressed, isNull);
  });

  testWidgets('Eject is disabled while it is in flight', (tester) async {
    await pumpCard(tester, drive(), onEject: () {}, isEjecting: true);

    expect(eject(tester).onPressed, isNull);
    expect(find.text('Ejecting…'), findsOneWidget);
  });

  testWidgets('an unmounted drive says it is safe to unplug', (tester) async {
    await pumpCard(tester, drive(mountPoint: '', isEnabled: false));
    expect(
      find.byKey(const ValueKey('device_card_safe_to_remove')),
      findsOneWidget,
    );

    await pumpCard(tester, drive());
    expect(
      find.byKey(const ValueKey('device_card_safe_to_remove')),
      findsNothing,
    );
  });
}
