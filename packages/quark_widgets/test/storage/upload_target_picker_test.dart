import 'package:flutter/material.dart';
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

void main() {
  testBothViewports('lists the targets and emits every action', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: UploadTargetPicker(
          targets: const [_internal, _usb],
          selected: _internal,
          onSelected: (t) => events.add('select:${t.serial}'),
          onCancel: () => events.add('cancel'),
          onConfirm: () => events.add('confirm'),
        ),
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
}
