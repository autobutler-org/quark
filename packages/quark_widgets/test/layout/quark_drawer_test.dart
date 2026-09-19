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

    final photos = tester.widget<ListTile>(
      find.byKey(const ValueKey('drawer_photos')),
    );
    expect(photos.selected, isTrue);
    final files = tester.widget<ListTile>(
      find.byKey(const ValueKey('drawer_files')),
    );
    expect(files.selected, isFalse);

    for (final label in [
      'Files',
      'Photos',
      'Trash',
      'Docs',
      'Sheets',
      'Devices',
      'Health',
      'Vault',
      'Jobs',
      'Settings',
    ]) {
      // The narrow viewport is shorter than the drawer, and its list only
      // builds the rows near the screen.
      await tester.scrollUntilVisible(find.text(label), 50);
      expect(find.text(label), findsOneWidget, reason: '$label is missing');
    }
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
        onTapJobs: () => tapped.add('jobs'),
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
    await tester.scrollUntilVisible(settings, 50);
    await tester.tap(settings);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  /// #2033: with more than one Quark saved, nothing in the signed-in app said
  /// which one was on screen, so an upload could land on the wrong device
  /// without a single hint beforehand.
  testBothViewports('names the Quark it is signed in to', (tester, size) async {
    await pumpAt(
      tester,
      const QuarkDrawer(
        activeSection: QuarkDrawerSection.files,
        hostName: 'Cabin',
        hostAddress: 'cabin.local:8443',
      ),
      size: size,
    );

    expect(find.text('Cabin'), findsOneWidget);
    expect(find.text('cabin.local:8443'), findsOneWidget);
  });

  testWidgets('falls back to the product name when no host is passed', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const QuarkDrawer(activeSection: QuarkDrawerSection.files),
      size: narrowViewport,
    );

    expect(find.text('Quark'), findsOneWidget);
    expect(find.byKey(const ValueKey('drawer_host')), findsNothing);
  });

  testWidgets('the host block is how you get to switching Quarks', (
    tester,
  ) async {
    var taps = 0;
    await pumpAt(
      tester,
      QuarkDrawer(
        activeSection: QuarkDrawerSection.files,
        hostName: 'Cabin',
        hostAddress: 'cabin.local',
        onTapHost: () => taps++,
      ),
      size: narrowViewport,
    );

    await tester.tap(find.byKey(const ValueKey('drawer_host')));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('a long nickname and address do not overflow a phone', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const QuarkDrawer(
        activeSection: QuarkDrawerSection.files,
        hostName: 'The Quark in the basement behind the water heater',
        hostAddress: 'https://quark-in-the-basement.home.local:8443',
      ),
      size: narrowViewport,
    );

    expect(tester.takeException(), isNull);
  });
}
