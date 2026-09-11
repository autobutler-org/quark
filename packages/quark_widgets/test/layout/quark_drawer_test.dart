import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testBothViewports('lists every section and marks the active one', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const QuarkDrawer(activeSection: QuarkDrawerSection.photos),
      size: size,
    );

    for (final label in [
      'Files',
      'Photos',
      'Trash',
      'Docs',
      'Sheets',
      'Devices',
      'Health',
      'Vault',
      'Settings',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '$label is missing');
    }

    final photos = tester.widget<ListTile>(
      find.byKey(const ValueKey('drawer_photos')),
    );
    expect(photos.selected, isTrue);
    final files = tester.widget<ListTile>(
      find.byKey(const ValueKey('drawer_files')),
    );
    expect(files.selected, isFalse);
  });

  testBothViewports('calls back for the row that was tapped', (
    tester,
    size,
  ) async {
    final tapped = <String>[];
    await pumpAt(
      tester,
      QuarkDrawer(
        activeSection: QuarkDrawerSection.files,
        onTapFiles: () => tapped.add('files'),
        onTapPhotos: () => tapped.add('photos'),
        onTapTrash: () => tapped.add('trash'),
        onTapDocs: () => tapped.add('docs'),
        onTapSheets: () => tapped.add('sheets'),
        onTapDevices: () => tapped.add('devices'),
        onTapHealth: () => tapped.add('health'),
        onTapVault: () => tapped.add('vault'),
        onTapSettings: () => tapped.add('settings'),
      ),
      size: size,
    );

    for (final section in QuarkDrawerSection.values) {
      // The narrow viewport is shorter than the drawer; it scrolls.
      final row = find.byKey(ValueKey('drawer_${section.name}'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pump();
    }

    expect(tapped, QuarkDrawerSection.values.map((s) => s.name).toList());
  });

  testWidgets('tapping a row with no handler does nothing', (tester) async {
    await pumpAt(
      tester,
      const QuarkDrawer(activeSection: QuarkDrawerSection.vault),
      size: narrowViewport,
    );

    final settings = find.byKey(const ValueKey('drawer_settings'));
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
