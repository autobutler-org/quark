import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/pages/settings_page.dart';
import 'package:quark/pages/system_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';

import '../support/unreachable_quark.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #1637: with a Quark configured but out of reach, every page that loads from
/// it used to render the raw connection failure. A page with nothing left to
/// show takes the full disconnected state; Settings, which stays usable
/// because the address is fixed there, takes the banner instead.
void main() {
  final settings = AppSettings.instance;

  Future<void> clearHosts() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  }

  late HttpOverrides? priorOverrides;

  /// Layout errors raised while a page is on screen.
  ///
  /// Settings overflows its own app bar by 28px at this viewport — the
  /// [QuarkBrandButton] against a fixed `leadingWidth` — with or without any
  /// of this. Collecting rather than throwing keeps that pre-existing failure
  /// from masking what is under test, while [expectOnlyKnownLayoutErrors]
  /// still fails on anything new.
  late List<String> layoutErrors;
  late void Function() stopWatchingErrors;

  void expectOnlyKnownLayoutErrors() {
    stopWatchingErrors();
    for (final error in layoutErrors) {
      expect(error, contains('overflowed'));
    }
  }

  setUp(() async {
    priorOverrides = HttpOverrides.current;
    HttpOverrides.global = UnreachableQuarkHttpOverrides();
    await clearHosts();
    await settings.addHost(
      HostEntry(name: 'Home', hostAddress: 'https://quark.local'),
    );
    await settings.acceptTerms();
  });

  tearDown(() async {
    HttpOverrides.global = priorOverrides;
    await clearHosts();
  });

  /// Mounts [page] at [path] under a router carrying the routes the drawer and
  /// the disconnected state's "Check the address" button link to.
  Future<void> pumpPage(
    WidgetTester tester,
    String path,
    Widget Function(BuildContext) page, {
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Installed here, not in setUp: testWidgets replaces FlutterError.onError
    // when the test body starts, so an earlier hook would be overwritten.
    layoutErrors = <String>[];
    final priorOnError = FlutterError.onError;
    var restored = false;
    FlutterError.onError = (details) =>
        layoutErrors.add(details.exceptionAsString());
    stopWatchingErrors = () {
      if (restored) return;
      restored = true;
      FlutterError.onError = priorOnError;
    };
    addTearDown(stopWatchingErrors);

    final router = GoRouter(
      initialLocation: path,
      routes: [
        GoRoute(path: path, builder: (context, _) => page(context)),
        if (path != AppRoutes.settings)
          GoRoute(
            path: AppRoutes.settingsTab(SettingsTab.general),
            builder: (_, _) => const Scaffold(body: Text('settings')),
          ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    if (settle) {
      await tester.pumpAndSettle();
      return;
    }
    // Settings never settles: its SBOM section keeps a spinner turning for a
    // source that is not the Quark. Pump far enough for every Quark-bound
    // load to have failed instead.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  group('a page with nothing left to show', () {
    testWidgets('takes the full disconnected state', (tester) async {
      await pumpPage(
        tester,
        AppRoutes.systemTab(SystemTab.health),
        (_) => const SystemPage(),
      );
      expectOnlyKnownLayoutErrors();

      expect(find.byType(QuarkDisconnectedView), findsOneWidget);
      expect(find.text(quarkDisconnectedHeadline), findsOneWidget);
      for (final step in quarkTroubleshootingSteps) {
        expect(find.text(step), findsOneWidget);
      }
    });

    testWidgets('never shows the underlying exception', (tester) async {
      await pumpPage(
        tester,
        AppRoutes.systemTab(SystemTab.health),
        (_) => const SystemPage(),
      );
      expectOnlyKnownLayoutErrors();

      // The leakage from the bug report, in the shape it arrived.
      expect(find.textContaining('ClientException'), findsNothing);
      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.textContaining('errno'), findsNothing);
      expect(find.text('Failed to load health data'), findsNothing);
    });

    testWidgets('offers a way to the address that failed', (tester) async {
      await pumpPage(
        tester,
        AppRoutes.systemTab(SystemTab.health),
        (_) => const SystemPage(),
      );
      expectOnlyKnownLayoutErrors();

      expect(find.text('https://quark.local'), findsOneWidget);
      await tester.tap(find.text('Check the address'));
      await tester.pumpAndSettle();

      expect(find.text('settings'), findsOneWidget);
    });
  });

  group('Settings, which stays usable', () {
    testWidgets('takes the banner rather than the full state', (tester) async {
      await pumpPage(
        tester,
        AppRoutes.settings,
        (_) => const SettingsPage(),
        settle: false,
      );
      expectOnlyKnownLayoutErrors();

      expect(find.byType(QuarkDisconnectedBanner), findsOneWidget);
      expect(find.byType(QuarkDisconnectedView), findsNothing);
    });

    testWidgets('keeps host management reachable underneath it', (
      tester,
    ) async {
      await pumpPage(
        tester,
        AppRoutes.settings,
        (_) => const SettingsPage(),
        settle: false,
      );
      expectOnlyKnownLayoutErrors();

      // The point of the page while disconnected: fixing the address.
      expect(find.text('https://quark.local'), findsWidgets);
    });

    testWidgets('replaces the per-section exception dumps', (tester) async {
      await pumpPage(
        tester,
        AppRoutes.settings,
        (_) => const SettingsPage(),
        settle: false,
      );
      expectOnlyKnownLayoutErrors();

      expect(find.textContaining('ClientException'), findsNothing);
      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.textContaining('errno'), findsNothing);
      expect(
        find.textContaining('Failed to load remote access status'),
        findsNothing,
      );
      // The SBOM section lists per-source failures; the Go source is the only
      // one that comes from the Quark, and it must not carry the exception.
      expect(find.textContaining('Go SBOM: Client'), findsNothing);
    });
  });
}
