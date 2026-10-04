import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/feature_flag.dart';
import 'package:quark/pages/account_and_data_page.dart';
import 'package:quark/pages/settings_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/text_scale.dart';
import '../support/unreachable_quark.dart';

/// #2606, #2603, #2605: every Settings tab, and the account and data page it
/// drills into, survives 200% text on a phone and a desktop, top to bottom,
/// and every control on them is labeled and big enough to hit.
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
    settings.featureFlags.value = const [];
  }

  setUp(() async {
    priorOverrides = HttpOverrides.current;
    HttpOverrides.global = UnreachableQuarkHttpOverrides();
    await reset();
    // Signed in as an admin with a beta on, so every row is on screen.
    await settings.addHost(
      HostEntry(name: 'Quark', hostAddress: 'https://quark.local'),
    );
    await settings.setSessionToken('a-session');
    await settings.setUsername('ada');
    settings.isAdmin.value = true;
    settings.featureFlags.value = const [
      FeatureFlag(
        key: FeatureFlag.chat,
        label: 'Chat',
        description: 'Hides chat; stored data is kept.',
        enabled: true,
      ),
    ];
  });

  tearDown(() async {
    HttpOverrides.global = priorOverrides;
    await reset();
  });

  /// Pumps [page] far enough for every Quark-bound load to fail. Settings
  /// never settles, since the SBOM spinner keeps turning.
  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: page,
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Checks the screen, then scrolls the page's list a screen at a time and
  /// checks again, so rows a lazy list has not built yet are checked too.
  Future<void> expectWholePageAccessible(WidgetTester tester) async {
    final list = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    for (var i = 0; i < 20; i++) {
      expect(tester.takeException(), isNull);
      await expectTapTargetGuidelines(tester);
      final position = tester.state<ScrollableState>(list).position;
      if (position.pixels >= position.maxScrollExtent) break;
      position.jumpTo(position.pixels + position.viewportDimension * 0.8);
      await tester.pump();
    }
  }

  for (final tab in SettingsTab.values) {
    testLargeText('the ${tab.slug} tab lays out', (tester, _) async {
      await pumpPage(tester, SettingsPage(tab: tab, onTabSelected: (_) {}));
      await expectWholePageAccessible(tester);
    });
  }

  testLargeText('account and data lays out', (tester, _) async {
    await pumpPage(tester, const AccountAndDataPage());
    await expectWholePageAccessible(tester);
  });
}
