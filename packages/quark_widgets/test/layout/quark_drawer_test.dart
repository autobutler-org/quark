import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The drawer draws a row only for a destination the caller offers, which is
/// how admin-only pages stay out of a non-admin's drawer (#1662).
void main() {
  Map<QuarkDrawerSection, void Function()> everyCallback(List<String> tapped) =>
      {
        for (final section in QuarkDrawerSection.values)
          section: () => tapped.add(section.name),
      };

  QuarkDrawer drawerWith(
    QuarkDrawerSection active,
    Map<QuarkDrawerSection, void Function()> callbacks,
  ) => QuarkDrawer(
    activeSection: active,
    onTapFiles: callbacks[QuarkDrawerSection.files],
    onTapPhotos: callbacks[QuarkDrawerSection.photos],
    onTapTrash: callbacks[QuarkDrawerSection.trash],
    onTapDocs: callbacks[QuarkDrawerSection.docs],
    onTapSheets: callbacks[QuarkDrawerSection.sheets],
    onTapSystem: callbacks[QuarkDrawerSection.system],
    onTapVault: callbacks[QuarkDrawerSection.vault],
    onTapUsers: callbacks[QuarkDrawerSection.users],
    onTapSettings: callbacks[QuarkDrawerSection.settings],
  );

  testBothViewports('lists every offered section and marks the active one', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      drawerWith(QuarkDrawerSection.photos, everyCallback([])),
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

    // Top to bottom: the narrow viewport is shorter than the drawer, and its
    // list only builds the rows that are scrolled into view.
    for (final label in [
      'Files',
      'Photos',
      'Trash',
      'Docs',
      'Sheets',
      'System',
      'Vault',
      'Users',
      'Settings',
    ]) {
      await tester.scrollUntilVisible(find.text(label), 50);
      expect(find.text(label), findsOneWidget, reason: '$label is missing');
    }
    expect(tester.takeException(), isNull);
  });

  testBothViewports('calls back for the row that was tapped', (
    tester,
    size,
  ) async {
    final tapped = <String>[];
    await pumpAt(
      tester,
      drawerWith(QuarkDrawerSection.files, everyCallback(tapped)),
      size: size,
    );

    for (final section in QuarkDrawerSection.values) {
      // The narrow viewport is shorter than the drawer; it scrolls.
      final row = find.byKey(ValueKey('drawer_${section.name}'));
      await tester.scrollUntilVisible(row, 50);
      await tester.tap(row);
      await tester.pump();
    }

    expect(tapped, QuarkDrawerSection.values.map((s) => s.name).toList());
  });

  testBothViewports('draws no row for a section without a callback', (
    tester,
    size,
  ) async {
    final callbacks = everyCallback([])
      ..remove(QuarkDrawerSection.users)
      ..remove(QuarkDrawerSection.vault);
    await pumpAt(
      tester,
      drawerWith(QuarkDrawerSection.files, callbacks),
      size: size,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('drawer_settings')),
      50,
    );
    expect(find.byKey(const ValueKey('drawer_users')), findsNothing);
    expect(find.text('Users'), findsNothing);
    expect(find.byKey(const ValueKey('drawer_vault')), findsNothing);
    expect(find.byKey(const ValueKey('drawer_settings')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('draws the users row once it is offered', (
    tester,
    size,
  ) async {
    final tapped = <String>[];
    await pumpAt(
      tester,
      QuarkDrawer(
        activeSection: QuarkDrawerSection.files,
        onTapUsers: () => tapped.add('users'),
      ),
      size: size,
    );

    await tester.tap(find.byKey(const ValueKey('drawer_users')));
    await tester.pump();

    expect(tapped, ['users']);
    expect(find.byKey(const ValueKey('drawer_files')), findsNothing);
  });

  for (final (label, brightness) in [
    ('dark', Brightness.dark),
    ('light', Brightness.light),
  ]) {
    testWidgets('$label: lays out without an exception', (tester) async {
      await pumpAt(
        tester,
        drawerWith(QuarkDrawerSection.users, everyCallback([])),
        brightness: brightness,
      );
      expect(tester.takeException(), isNull);
    });
  }

  /// #2033: with more than one Quark saved, nothing in the signed-in app said
  /// which one was on screen, so an upload could land on the wrong device
  /// without a single hint beforehand.
  testBothViewports('names the Quark it is signed in to', (tester, size) async {
    await pumpAt(
      tester,
      const QuarkDrawer(
        activeSection: QuarkDrawerSection.files,
        hosts: [HostItem(name: 'Cabin', address: 'cabin.local:8443')],
        activeHostIndex: 0,
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

  testWidgets('a long nickname and address do not overflow a phone', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const QuarkDrawer(
        activeSection: QuarkDrawerSection.files,
        hosts: [
          HostItem(
            name: 'The Quark in the basement behind the water heater',
            address: 'https://quark-in-the-basement.home.local:8443',
          ),
          HostItem(name: 'Cabin', address: 'cabin.local'),
        ],
        activeHostIndex: 0,
        onSelectHost: _ignore,
      ),
      size: narrowViewport,
    );

    expect(tester.takeException(), isNull);
  });

  /// #2230: switching Quarks used to mean a trip to Settings.
  const hosts = [
    HostItem(name: 'Home', address: 'quark.home.local'),
    HostItem(name: 'Cabin', address: 'cabin.local:8443'),
  ];

  testBothViewports('a single Quark is a label, not a menu', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkDrawer(
        activeSection: QuarkDrawerSection.files,
        hosts: const [HostItem(name: 'Home', address: 'quark.home.local')],
        activeHostIndex: 0,
        onSelectHost: (_) => fail('no menu to select from'),
      ),
      size: size,
    );

    expect(find.text('Home'), findsOneWidget);
    expect(find.byKey(const ValueKey('drawer_host_header')), findsNothing);
    expect(find.byIcon(Icons.unfold_more_rounded), findsNothing);
  });

  testBothViewports('lists every Quark with the active one checked', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkDrawer(
        activeSection: QuarkDrawerSection.files,
        hosts: hosts,
        activeHostIndex: 1,
        onSelectHost: (_) {},
      ),
      size: size,
    );

    expect(find.byIcon(Icons.unfold_more_rounded), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('drawer_host_header')));
    await tester.pumpAndSettle();

    final home = tester.widget<CheckedPopupMenuItem<int>>(
      find.byKey(const ValueKey('drawer_host_0')),
    );
    final cabin = tester.widget<CheckedPopupMenuItem<int>>(
      find.byKey(const ValueKey('drawer_host_1')),
    );
    expect(home.checked, isFalse);
    expect(cabin.checked, isTrue);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('picking a Quark calls back with its index', (
    tester,
    size,
  ) async {
    final picked = <int>[];
    await pumpAt(
      tester,
      QuarkDrawer(
        activeSection: QuarkDrawerSection.files,
        hosts: hosts,
        activeHostIndex: 0,
        onSelectHost: picked.add,
      ),
      size: size,
    );

    await tester.tap(find.byKey(const ValueKey('drawer_host_header')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drawer_host_1')));
    await tester.pumpAndSettle();

    expect(picked, [1]);
  });

  testBothViewports('the menu opens under the switcher icon', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkDrawer(
        activeSection: QuarkDrawerSection.files,
        hosts: hosts,
        activeHostIndex: 0,
        onSelectHost: (_) {},
      ),
      size: size,
    );

    final icon = tester.getRect(find.byIcon(Icons.unfold_more_rounded));
    await tester.tap(find.byKey(const ValueKey('drawer_host_header')));
    await tester.pumpAndSettle();

    final menu = tester.getRect(
      find
          .ancestor(
            of: find.byKey(const ValueKey('drawer_host_0')),
            matching: find.byType(Material),
          )
          .last,
    );
    expect(menu.right, closeTo(icon.right, 1));
    expect(menu.top, greaterThanOrEqualTo(icon.bottom));
    expect(find.byTooltip('Switch Quark'), findsNothing);
  });
}

void _ignore(int _) {}
