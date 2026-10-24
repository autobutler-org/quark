import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/feature_flag.dart';
import 'package:quark/pages/account_and_data_page.dart';
import 'package:quark/pages/settings_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/text_scale.dart';
import '../support/unreachable_quark.dart';
import '../support/secure_storage.dart';

/// #2606, #2603, #2605: every Settings tab, and the account and data page it
/// drills into, survives 200% text on a phone and a desktop, top to bottom,
/// and every control on them is labeled and big enough to hit.
void main() {
  final settings = AppSettings.instance;

  setUpAll(mockSecureStorage);

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
    // Signed in as an admin with a feature flag on, so every row is on screen.
    await settings.addHost(
      HostEntry(name: 'Quark', hostAddress: 'https://quark.local'),
    );
    await settings.setSessionToken('a-session');
    await settings.setUsername('ada');
    settings.isAdmin.value = true;
    settings.featureFlags.value = const [
      FeatureFlag(
        key: 'notes',
        label: 'Notes',
        description: 'Hides Notes; stored notes are kept.',
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

  /// The installed-version line. The dropdown repeats the same string at the
  /// default size, so the font size is what picks out the one on display.
  Finder installedVersion(String version) => find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        widget.data == version &&
        widget.style?.fontSize == 28,
  );

  Finder updateButton() => find.byKey(const ValueKey('settings_start_update'));

  Future<void> pumpUpdates(WidgetTester tester, SettingsPage page) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: page,
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (updateButton().evaluate().isNotEmpty) break;
    }
    await tester.scrollUntilVisible(
      updateButton(),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }

  FilledButton buttonOf(WidgetTester tester) =>
      tester.widget<FilledButton>(updateButton());

  // #3218: the POST returns while the old process is still serving. One tap
  // stays on Restarting until a later read reports the new version.
  testWidgets('one update tap waits until the new version is serving', (
    tester,
  ) async {
    final installed = <String, dynamic>{'semver': '0.1.0', 'gitCommit': ''};
    var failNext = false;
    var updateCalls = 0;
    await pumpUpdates(
      tester,
      SettingsPage(
        tab: SettingsTab.updates,
        onTabSelected: (_) {},
        getInstalledVersion: () async {
          if (failNext) {
            failNext = false;
            throw Exception('connection refused');
          }
          return installed;
        },
        listAvailableVersions: () async => [
          {'version': '0.2.0'},
        ],
        updateToVersion: (version) async {
          updateCalls++;
          expect(version, '0.2.0');
        },
        restartPollInterval: const Duration(milliseconds: 50),
        restartTimeout: const Duration(seconds: 2),
      ),
    );

    expect(installedVersion('0.1.0'), findsOneWidget);
    expect(buttonOf(tester).onPressed, isNotNull);

    await tester.tap(updateButton());
    await tester.pump();

    expect(updateCalls, 1);
    expect(find.text('Restarting...'), findsOneWidget);
    expect(buttonOf(tester).onPressed, isNull);
    expect(installedVersion('0.1.0'), findsOneWidget);

    // The server goes away, then the old process answers once more. Neither
    // ends the wait or starts a second install.
    failNext = true;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(updateCalls, 1);
    expect(find.text('Restarting...'), findsOneWidget);
    expect(buttonOf(tester).onPressed, isNull);
    expect(installedVersion('0.1.0'), findsOneWidget);

    installed['semver'] = '0.2.0';
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (installedVersion('0.2.0').evaluate().isNotEmpty) break;
    }

    expect(updateCalls, 1);
    expect(installedVersion('0.2.0'), findsOneWidget);
    expect(find.text('Restarting...'), findsNothing);
    expect(find.text('Update started for 0.2.0'), findsNothing);
    expect(buttonOf(tester).onPressed, isNotNull);
  });

  testWidgets('an update that never restarts shows an error', (tester) async {
    var updateCalls = 0;
    await pumpUpdates(
      tester,
      SettingsPage(
        tab: SettingsTab.updates,
        onTabSelected: (_) {},
        getInstalledVersion: () async => {'semver': '0.1.0', 'gitCommit': ''},
        listAvailableVersions: () async => [
          {'version': '0.2.0'},
        ],
        updateToVersion: (_) async {
          updateCalls++;
        },
        restartPollInterval: const Duration(milliseconds: 50),
        restartTimeout: const Duration(milliseconds: 200),
      ),
    );

    await tester.tap(updateButton());
    await tester.pump();
    expect(find.text('Restarting...'), findsOneWidget);

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find
          .byKey(const ValueKey('settings_update_error'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    expect(updateCalls, 1);
    expect(find.text(Errors.updateDidNotFinish), findsOneWidget);
    expect(installedVersion('0.1.0'), findsOneWidget);
    expect(installedVersion('0.2.0'), findsNothing);
    expect(find.text('Restarting...'), findsNothing);
    expect(find.textContaining('Update started'), findsNothing);
  });

  testWidgets('a refused update does not show a restart', (tester) async {
    var updateCalls = 0;
    await pumpUpdates(
      tester,
      SettingsPage(
        tab: SettingsTab.updates,
        onTabSelected: (_) {},
        getInstalledVersion: () async => {'semver': '0.1.0', 'gitCommit': ''},
        listAvailableVersions: () async => [
          {'version': '0.2.0'},
        ],
        updateToVersion: (_) async {
          updateCalls++;
          throw const ApiException(409, 'Failed to perform update');
        },
        restartPollInterval: const Duration(milliseconds: 50),
        restartTimeout: const Duration(milliseconds: 200),
      ),
    );

    await tester.tap(updateButton());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(updateCalls, 1);
    expect(find.text(Errors.updateAlreadyInProgress), findsOneWidget);
    expect(find.text('Restarting...'), findsNothing);
    expect(installedVersion('0.1.0'), findsOneWidget);
    expect(buttonOf(tester).onPressed, isNotNull);
  });
}
