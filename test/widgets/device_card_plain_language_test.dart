import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/storage_devices/device_card.dart';

/// #2047: the Devices page led with "Root Volume" and `/ · overlay`, which
/// reads like a Linux admin panel rather than a household's own storage. The
/// backend stopped saying "Root Volume" (see `rootDeviceName`); the card now
/// says what the drive is before it says where it is mounted.
void main() {
  StorageDevice device({
    required bool isInternal,
    String name = 'Built-in storage',
  }) {
    return StorageDevice(
      name: name,
      devicePath: '/dev/root',
      mountPoint: '/',
      fileSystem: 'overlay',
      totalBytes: 100,
      usedBytes: 50,
      availableBytes: 50,
      isInternal: isInternal,
      isEnabled: true,
    );
  }

  Future<void> pumpCard(WidgetTester tester, StorageDevice d) async {
    tester.view.physicalSize = const Size(700, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DeviceCard(device: d, isMounting: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the Quark\'s own disk says what it is', (tester) async {
    await pumpCard(tester, device(isInternal: true));

    expect(find.text('Inside your Quark'), findsOneWidget);
    expect(find.text('Built-in storage'), findsOneWidget);
  });

  testWidgets('an attached drive says what it is', (tester) async {
    await pumpCard(tester, device(isInternal: false, name: 'Backup'));

    expect(find.text('Plugged-in drive'), findsOneWidget);
  });

  testWidgets('the technical detail is still there, just not first', (
    tester,
  ) async {
    await pumpCard(tester, device(isInternal: true));

    final kind = tester.getRect(find.byKey(const ValueKey('device_card_kind')));
    final path = tester.getRect(find.text('/  ·  overlay'));
    expect(path.top, greaterThan(kind.top));
  });
}
