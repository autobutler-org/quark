import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/pages/settings_page.dart';
import 'package:quark/pages/terms_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';

/// Saving a Quark from the Settings dialog changes the active host, which
/// re-runs the router's terms gate and replaces the Settings page (#1623).
/// The dialog used to save from inside its own button, so that replacement
/// happened while the dialog was still on screen — tearing the settings
/// subtree down underneath a live route. On web that surfaced as a disposed
/// TextEditingController, a wild RenderFlex overflow, and a failed
/// `_dependents.isEmpty` assertion in InheritedElement.
void main() {
  final settings = AppSettings.instance;

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() {
    // The session token lives in secure storage on native platforms, and
    // there's no plugin behind it in a unit test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  Future<void> reset() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
    await settings.setSessionToken(null);
  }

  setUp(() async {
    await reset();
    // Saving a host checks the address first (#2032). This test is about what
    // the dialog does to the route stack, so the Quark answers.
    hostReachabilityProbe = (_) async => true;
  });
  tearDown(() async {
    await reset();
    hostReachabilityProbe = AuthService.isReachable;
  });

  /// Whether the dialog route was still on the navigator when the active host
  /// changed. Saving from inside the dialog's own button made the terms gate
  /// replace the page underneath a live dialog route; saving after the pop
  /// leaves nothing above the page to tear down.
  late bool dialogStillPushedWhenHostChanged;
  late List<String> errors;
  late void Function() stopWatchingErrors;

  /// Settings is behind the auth gate: with no Quark configured the gate sends
  /// the user to login (#1639), and so does a signed-out user whose Quark is
  /// unreachable (#1624). An accepted host plus a session is what puts Settings
  /// on screen at all; the flow under test is then adding a *second* Quark
  /// from it.
  const seedAddress = 'http://127.0.0.1:1';

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await settings.addHost(HostEntry(name: 'Seed', hostAddress: seedAddress));
    await settings.acceptTerms();
    await settings.setSessionToken('test-session');

    errors = <String>[];
    final priorOnError = FlutterError.onError;
    var restored = false;
    // Collected rather than thrown, so a failure names the flow that produced
    // it. Must be restored before any expect() or the binding asserts.
    FlutterError.onError = (details) => errors.add(details.exceptionAsString());
    stopWatchingErrors = () {
      if (restored) return;
      restored = true;
      FlutterError.onError = priorOnError;
    };
    addTearDown(stopWatchingErrors);

    final navigatorKey = GlobalKey<NavigatorState>();
    dialogStillPushedWhenHostChanged = false;
    void watch() {
      dialogStillPushedWhenHostChanged =
          navigatorKey.currentState?.canPop() ?? false;
    }

    settings.activeHostNotifier.addListener(watch);
    addTearDown(() => settings.activeHostNotifier.removeListener(watch));

    final router = GoRouter(
      navigatorKey: navigatorKey,
      initialLocation: AppRoutes.settings,
      redirect: authRedirect,
      refreshListenable: routerRefreshListenable,
      routes: [
        GoRoute(
          path: AppRoutes.files,
          builder: (_, _) => const Scaffold(body: Text('files')),
        ),
        GoRoute(
          path: AppRoutes.settings,
          builder: (_, _) => const SettingsPage(),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (_, _) => const Scaffold(body: Text('login')),
        ),
        GoRoute(path: AppRoutes.terms, builder: (_, _) => const TermsPage()),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(const Duration(seconds: 1));
    // The Settings page's own network failures aren't what's under test.
    errors.clear();
  }

  /// The Settings page keeps progress indicators spinning while its network
  /// calls are in flight, so `pumpAndSettle` never returns here.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('Add Quark'), warnIfMissed: false);
    await settle(tester);
  }

  Future<void> fillIn(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, 'My Quark');
    await tester.enterText(
      find.byType(TextField).last,
      'http://new-quark.local',
    );
    await tester.pump();
  }

  testWidgets('saving pops the dialog before the host changes', (tester) async {
    await pumpSettings(tester);
    await openDialog(tester);
    await fillIn(tester);

    await tester.tap(find.text('Save'));
    await settle(tester);
    stopWatchingErrors();

    expect(
      dialogStillPushedWhenHostChanged,
      isFalse,
      reason: 'the dialog must be popped before the terms gate re-runs',
    );
    expect(settings.hosts.last.hostAddress, 'http://new-quark.local');
    expect(settings.activeHost, 'http://new-quark.local');
    expect(find.byType(TermsPage), findsOneWidget);
    expect(errors, isEmpty);
  });

  // The reported trigger: Enter in the address field rather than a click.
  testWidgets('pressing Enter in the address field saves cleanly', (
    tester,
  ) async {
    await pumpSettings(tester);
    await openDialog(tester);
    await fillIn(tester);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    stopWatchingErrors();

    expect(dialogStillPushedWhenHostChanged, isFalse);
    expect(settings.hosts.last.hostAddress, 'http://new-quark.local');
    expect(settings.activeHost, 'http://new-quark.local');
    expect(find.byType(TermsPage), findsOneWidget);
    expect(errors, isEmpty);
  });

  testWidgets('cancelling saves nothing and leaves settings up', (
    tester,
  ) async {
    await pumpSettings(tester);
    await openDialog(tester);
    await fillIn(tester);

    await tester.tap(find.text('Cancel'));
    await settle(tester);
    stopWatchingErrors();

    expect(settings.hosts.single.hostAddress, seedAddress);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(errors, isEmpty);
  });

  testWidgets('an empty field does not save or close', (tester) async {
    await pumpSettings(tester);
    await openDialog(tester);

    await tester.enterText(find.byType(TextField).first, 'My Quark');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await settle(tester);
    stopWatchingErrors();

    expect(settings.hosts.single.hostAddress, seedAddress);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
