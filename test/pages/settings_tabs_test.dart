import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/settings_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';

import '../support/unreachable_quark.dart';

/// #2350: Settings is five tabs, each with its own URL. Every tab lays out on
/// a phone and on a desktop, shows what it is meant to hold, and reports a
/// tab the user picks so the router can move the address bar.
void main() {
  final settings = AppSettings.instance;

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  late HttpOverrides? priorOverrides;

  Future<void> reset() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
    await settings.setSessionToken(null);
    settings.isAdmin.value = false;
  }

  setUp(() async {
    priorOverrides = HttpOverrides.current;
    HttpOverrides.global = UnreachableQuarkHttpOverrides();
    await reset();
    // Signed in as an admin, so every admin-only row is on screen too.
    await settings.addHost(
      HostEntry(name: 'Quark', hostAddress: 'https://quark.local'),
    );
    await settings.setSessionToken('a-session');
    await settings.setUsername('ada');
    settings.isAdmin.value = true;
  });

  tearDown(() async {
    HttpOverrides.global = priorOverrides;
    await reset();
  });

  /// Pumps Settings on [tab] at [size]. It never settles, since the SBOM
  /// spinner keeps turning, so it pumps far enough for every load to fail.
  Future<List<SettingsTab>> pumpAt(
    WidgetTester tester,
    SettingsTab tab,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final selected = <SettingsTab>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(tab: tab, onTabSelected: selected.add),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    return selected;
  }

  /// The open tab's list. Found by type, since the tab bar and the pages
  /// under it scroll too.
  Finder tabList() => find
      .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
      .first;

  /// A line only that tab shows.
  const marker = {
    SettingsTab.general: 'Backend hosts',
    SettingsTab.account: 'Sign out',
    SettingsTab.network: 'Remote access',
    SettingsTab.updates: 'Quark version (installed)',
    SettingsTab.about: 'Software Bill of Materials',
  };

  const viewports = {'narrow': Size(360, 640), 'wide': Size(1280, 800)};

  for (final tab in SettingsTab.values) {
    for (final MapEntry(key: name, value: size) in viewports.entries) {
      testWidgets('the ${tab.slug} tab lays out, $name', (tester) async {
        await pumpAt(tester, tab, size);

        expect(tester.takeException(), isNull);
        // The disconnected banner heads the tab and fills a phone's screen,
        // so the tab's own content is further down.
        await tester.scrollUntilVisible(
          find.text(marker[tab]!),
          200,
          scrollable: tabList(),
        );
        expect(tester.takeException(), isNull);
        expect(find.text(marker[tab]!), findsOneWidget);
        for (final other in SettingsTab.values.where((t) => t != tab)) {
          expect(find.text(marker[other]!), findsNothing);
        }
      });
    }
  }

  testWidgets('keeps the destructive entries off the first tab', (
    tester,
  ) async {
    await pumpAt(tester, SettingsTab.general, const Size(1280, 800));

    expect(find.byKey(const ValueKey('settings_delete_account')), findsNothing);
    expect(find.byKey(const ValueKey('settings_reset_quark')), findsNothing);
  });

  testWidgets('links to the drives instead of listing them', (tester) async {
    await pumpAt(tester, SettingsTab.general, const Size(1280, 800));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings_open_storage')),
      200,
      scrollable: tabList(),
    );

    expect(find.byKey(const ValueKey('settings_open_storage')), findsOneWidget);
    expect(find.text('Mount'), findsNothing);
  });

  testWidgets('reports the tab the user picks', (tester) async {
    final selected = await pumpAt(
      tester,
      SettingsTab.general,
      const Size(1280, 800),
    );

    await tester.tap(find.byKey(const ValueKey('tab_network')));
    await tester.pump();

    expect(selected, [SettingsTab.network]);
  });
}
