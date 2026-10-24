import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/quark_widget.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

/// On iOS, [QuarkWidget.alertDialog] builds a CupertinoAlertDialog, which puts
/// no Material in the tree. Callers hand the same content to both branches, so
/// any Material widget in that content — a dropdown, an InkWell, a list tile —
/// used to trip `debugCheckHasMaterial` and take the whole dialog down with a
/// "No Material widget found" build error.
final _iOS = TargetPlatformVariant.only(TargetPlatform.iOS);

void main() {
  Future<void> openDialog(WidgetTester tester, Widget content) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => QuarkWidget.showDialog<void>(
              context,
              builder: (_) => QuarkWidget.alertDialog(
                title: const Text('Dialog'),
                content: content,
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Material content builds inside a Cupertino dialog', (
    tester,
  ) async {
    await openDialog(
      tester,
      DropdownButton<String>(
        value: 'a',
        items: const [DropdownMenuItem(value: 'a', child: Text('a'))],
        onChanged: (_) {},
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Dialog'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsOneWidget);
  }, variant: _iOS);

  testWidgets('an ink-splashing widget finds a Material ancestor', (
    tester,
  ) async {
    await openDialog(
      tester,
      InkWell(onTap: () {}, child: const Text('tap me')),
    );

    await tester.tap(find.text('tap me'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  }, variant: _iOS);

  testWidgets('the hosted Material does not paint over the dialog surface', (
    tester,
  ) async {
    await openDialog(tester, const Text('body'));

    final material = tester.widget<Material>(
      find
          .ancestor(of: find.text('body'), matching: find.byType(Material))
          .first,
    );
    expect(material.type, MaterialType.transparency);
  }, variant: _iOS);

  Future<void> openMoveRename(
    WidgetTester tester, {
    required List<StorageDevice> devices,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => promptForMoveRenamePath(
              context,
              startPath: '',
              initialName: 'notes.txt',
              devices: devices,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    // Settle, not a fixed pump: the dialog's fade transition paints nothing
    // until it finishes, and an overflow is only reported when it paints.
    await tester.pumpAndSettle();
  }

  testWidgets('the Move / Rename device picker opens on iOS', (tester) async {
    // The reported repro: two devices means the Material dropdown is shown.
    await openMoveRename(
      tester,
      devices: [
        _device('Internal', isInternal: true),
        _device('External', isInternal: false),
      ],
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Move / Rename'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<StorageDevice>), findsOneWidget);
  }, variant: _iOS);

  testWidgets('the device picker fits a phone-width dialog', (tester) async {
    // A dialog on a phone leaves the dropdown ~174 logical pixels. The device
    // name is arbitrary length, so the button has to give way rather than size
    // to its label and overflow its own row.
    setViewport(tester, const Size(320, 640));

    await openMoveRename(
      tester,
      devices: [
        _device('Samsung Portable SSD T7 Shield', isInternal: true),
        _device('External', isInternal: false),
      ],
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(DropdownButtonFormField<StorageDevice>), findsOneWidget);
  }, variant: _iOS);
}

StorageDevice _device(String name, {required bool isInternal}) {
  return StorageDevice(
    name: name,
    devicePath: '/dev/$name',
    mountPoint: '/mnt/$name',
    fileSystem: 'ext4',
    totalBytes: 1,
    usedBytes: 0,
    availableBytes: 1,
    isInternal: isInternal,
    isEnabled: true,
    serial: name,
  );
}
