import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/quark_widget_items.dart';
import 'package:quark/widgets/storage_devices/device_card.dart';

/// #4018: a drive plugged into a container after it started has no device
/// node, so the Quark reports it as needing a restart. The card says so in
/// plain words, offers no Mount that would fail with raw `mount` output, and
/// does not claim its health "could not be read".
void main() {
  StorageDevice drive({required bool needsRestart}) => StorageDevice(
    name: 'Fake - Drive',
    devicePath: '',
    mountPoint: '',
    fileSystem: '',
    totalBytes: 0,
    usedBytes: 0,
    availableBytes: 0,
    isInternal: false,
    isEnabled: false,
    serial: '2641R5D03639',
    needsRestart: needsRestart,
    health: const StorageDriveHealth(verdict: 'unknown'),
  );

  Future<void> pumpCard(WidgetTester tester, StorageDevice device) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DeviceCard(
                device: device,
                isMounting: false,
                onMount: () {},
              ),
            ),
          ),
        ),
      );

  testWidgets('a drive that needs a restart says so and offers no Mount', (
    tester,
  ) async {
    await pumpCard(tester, drive(needsRestart: true));

    expect(find.text(Errors.driveNeedsRestart), findsOneWidget);
    expect(
      find.byKey(const ValueKey('device_card_needs_restart_2641R5D03639')),
      findsOneWidget,
    );
    expect(find.text('Mount'), findsNothing);
    expect(find.text('Not mounted · safe to unplug'), findsNothing);
    expect(
      find.byKey(const ValueKey('drive_health_badge_2641R5D03639')),
      findsNothing,
    );
    expect(find.textContaining('could not be read'), findsNothing);
  });

  testWidgets('an ordinary unmounted drive still offers Mount', (tester) async {
    await pumpCard(tester, drive(needsRestart: false));

    expect(find.text(Errors.driveNeedsRestart), findsNothing);
    expect(find.text('Mount'), findsOneWidget);
  });

  test('needsRestart is read from the device status', () {
    StorageDevice parse(Map<String, dynamic> extra) => StorageDevice.fromJson({
      'name': 'Fake - Drive',
      'usbInfo': {'serial': '2641R5D03639'},
      ...extra,
    });

    expect(parse({'needsRestart': true}).needsRestart, isTrue);
    expect(parse({}).needsRestart, isFalse);
  });

  test('the copy names the restart and carries no mount output', () {
    expect(
      Errors.driveNeedsRestart,
      "Quark can't reach this drive until it restarts.",
    );
  });

  test('the upload picker names the restart, not Mount', () {
    expect(
      drive(needsRestart: true).toUploadTarget().unavailableReason,
      Errors.driveNeedsRestart,
    );
    expect(
      drive(needsRestart: false).toUploadTarget().unavailableReason,
      'Not enabled. Mount it under System > Storage.',
    );
  });
}
