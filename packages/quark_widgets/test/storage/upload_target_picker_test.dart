import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _internal = UploadTarget(
  serial: '',
  name: '',
  mountPoint: '/data',
  isInternal: true,
);
const _usb = UploadTarget(serial: 'usb-1', name: 'Backup drive');
const _off = UploadTarget(
  serial: 'usb-2',
  name: 'Old drive',
  mountPoint: '/mnt/off',
  unavailableReason: 'Mount it first',
);

void main() {
  testBothViewports('lists the targets and emits every action', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpInSheet(
      tester,
      UploadTargetPicker(
        targets: const [_internal, _usb],
        selected: _internal,
        onSelected: (t) => events.add('select:${t.serial}'),
        onCancel: () => events.add('cancel'),
        onConfirm: () => events.add('confirm'),
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Device'), findsOneWidget);
    expect(find.text('/data · Internal'), findsOneWidget);
    expect(find.text('Backup drive'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('upload_target_1')));
    await tester.tap(find.byKey(const ValueKey('upload_target_cancel')));
    await tester.tap(find.byKey(const ValueKey('upload_target_confirm')));

    expect(events, ['select:usb-1', 'cancel', 'confirm']);
  });

  // #3191: a drive that is plugged in but not enabled is shown, not hidden,
  // so the user learns what the missing step is.
  testBothViewports('an unavailable target shows its reason and cannot be '
      'chosen', (tester, size) async {
    final events = <String>[];
    await pumpInSheet(
      tester,
      UploadTargetPicker(
        targets: const [_internal, _usb, _off],
        selected: _internal,
        onSelected: (t) => events.add('select:${t.serial}'),
        onCancel: () {},
        onConfirm: () {},
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('/mnt/off · Mount it first'), findsOneWidget);
    final row = find.byKey(const ValueKey('upload_target_2'));
    expect(tester.widget<RadioListTile<UploadTarget>>(row).enabled, isFalse);

    await tester.tap(row);
    await tester.tap(find.byKey(const ValueKey('upload_target_1')));

    expect(events, ['select:usb-1']);
  });

  // #3194: the picker starts on the default storage device, so its row says
  // why.
  testBothViewports('the default storage device is labeled', (
    tester,
    size,
  ) async {
    const usbDefault = UploadTarget(
      serial: 'usb-1',
      name: 'Backup drive',
      mountPoint: '/mnt/usb',
      isDefault: true,
    );
    await pumpInSheet(
      tester,
      UploadTargetPicker(
        targets: const [_internal, usbDefault],
        selected: usbDefault,
        onSelected: (_) {},
        onCancel: () {},
        onConfirm: () {},
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('/mnt/usb · Default'), findsOneWidget);
    expect(find.text('/data · Internal'), findsOneWidget);
    expect(
      usbDefault,
      isNot(
        const UploadTarget(
          serial: 'usb-1',
          name: 'Backup drive',
          mountPoint: '/mnt/usb',
        ),
      ),
    );
  });

  // #3194: the sheet opens on its own only when there is no default device
  // to upload to, and its notice says why.
  testBothViewports('a notice reads above the list', (tester, size) async {
    await pumpInSheet(
      tester,
      UploadTargetPicker(
        targets: const [_internal, _usb],
        notice: 'No default storage device is connected.',
        selected: _internal,
        onSelected: (_) {},
        onCancel: () {},
        onConfirm: () {},
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    final notice = find.byKey(const ValueKey('upload_target_notice'));
    expect(
      tester.widget<Text>(notice).data,
      'No default storage device is connected.',
    );
    expect(
      tester.getTopLeft(notice).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('upload_target_0'))).dy,
      ),
    );
  });

  testWidgets('no notice shows nothing above the list', (tester) async {
    await pumpInSheet(
      tester,
      UploadTargetPicker(
        targets: const [_internal, _usb],
        selected: _internal,
        onSelected: (_) {},
        onCancel: () {},
        onConfirm: () {},
      ),
    );

    expect(find.byKey(const ValueKey('upload_target_notice')), findsNothing);
  });
}
