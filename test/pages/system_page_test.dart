import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/system_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/widgets/system/health_tab.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The System page (#2351): Health, Storage and Jobs as tabs of one page, each
/// at its own URL.
void main() {
  final settings = AppSettings.instance;

  /// The paths the page asked the Quark for, in order.
  final requests = <String>[];

  Future<void> clearHosts() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  }

  setUp(() async {
    requests.clear();
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request.url.path);
      return http.Response('', 404);
    });
    await clearHosts();
    await settings.addHost(
      HostEntry(name: 'Home', hostAddress: 'https://quark.local'),
    );
  });

  tearDown(() async {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
    await clearHosts();
  });

  Future<GoRouter> pumpSystem(
    WidgetTester tester,
    String location,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final r = GoRouter(
      initialLocation: location,
      routes: tabbedRoutes(
        path: AppRoutes.system,
        tabs: SystemTab.values,
        builder: (tab, onTabSelected) =>
            SystemPage(tab: tab, onTabSelected: onTabSelected),
      ),
    );
    addTearDown(r.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        routerConfig: r,
      ),
    );
    await tester.pumpAndSettle();
    return r;
  }

  String at(GoRouter r) => r.routerDelegate.currentConfiguration.uri.toString();

  int healthCalls() => requests.where((p) => p == '/api/v0/health').length;

  for (final (name, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('$name: /system opens on Health under one System bar', (
      tester,
    ) async {
      final r = await pumpSystem(tester, AppRoutes.system, size);

      expect(at(r), '/system/health');
      expect(find.text('System'), findsOneWidget);
      for (final tab in ['health', 'storage', 'jobs']) {
        expect(find.byKey(ValueKey('tab_$tab')), findsOneWidget);
      }
      expect(find.byType(HealthTab), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Disposing the page stops its refresh timers.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$name: Health stops polling once another tab is shown', (
      tester,
    ) async {
      final r = await pumpSystem(
        tester,
        AppRoutes.systemTab(SystemTab.health),
        size,
      );
      expect(healthCalls(), 1);

      await tester.tap(find.byKey(const ValueKey('tab_jobs')));
      await tester.pumpAndSettle();

      expect(at(r), '/system/jobs');
      expect(find.byType(HealthTab), findsNothing);
      expect(requests, contains('/api/v0/jobs'));

      // Past Health's 15-second interval, twice over.
      await tester.pump(const Duration(seconds: 40));
      expect(healthCalls(), 1);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('the bar refreshes the tab on screen', (tester) async {
    await pumpSystem(
      tester,
      AppRoutes.systemTab(SystemTab.jobs),
      const Size(1280, 800),
    );
    final jobsCalls = requests.where((p) => p == '/api/v0/jobs').length;

    // Past the refresh debounce, which reads the wall clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.tap(find.byKey(const ValueKey('refresh_button')));
    await tester.pumpAndSettle();

    expect(
      requests.where((p) => p == '/api/v0/jobs').length,
      greaterThan(jobsCalls),
    );
    expect(healthCalls(), 0);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a tab URL opens that tab on a cold load', (tester) async {
    await pumpSystem(
      tester,
      AppRoutes.systemTab(SystemTab.storage),
      const Size(1280, 800),
    );

    expect(find.byType(HealthTab), findsNothing);
    expect(requests, contains('/api/v0/storage/devices/status'));
    expect(healthCalls(), 0);

    await tester.pumpWidget(const SizedBox());
  });
}
