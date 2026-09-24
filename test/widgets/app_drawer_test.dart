import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every top-level page opens this one drawer, so what it offers and where
/// each row goes is decided here once (#1662). Admin-only pages are offered to
/// admins only (#1928).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  final scaffoldKey = GlobalKey<ScaffoldState>();

  setUp(() => settings.isAdmin.value = false);
  tearDown(() => settings.isAdmin.value = false);

  Widget page(String name, QuarkDrawerSection section) => Scaffold(
    key: name == 'files' ? scaffoldKey : null,
    drawer: AppDrawer(activeSection: section),
    body: Text('$name page'),
  );

  Future<void> pumpDrawer(WidgetTester tester) async {
    // Tall enough that the drawer's lazy list builds every row.
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: AppRoutes.files,
      routes: [
        GoRoute(
          path: AppRoutes.files,
          builder: (_, _) => page('files', QuarkDrawerSection.files),
        ),
        GoRoute(
          path: AppRoutes.photos,
          builder: (_, _) => page('photos', QuarkDrawerSection.photos),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (_, _) => const Text('login page'),
        ),
        GoRoute(
          path: AppRoutes.vault,
          builder: (_, _) => page('vault', QuarkDrawerSection.vault),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
  }

  testWidgets('offers every page to an admin and marks the current one', (
    tester,
  ) async {
    settings.isAdmin.value = true;
    await pumpDrawer(tester);

    for (final section in [
      QuarkDrawerSection.files,
      QuarkDrawerSection.photos,
      QuarkDrawerSection.trash,
      QuarkDrawerSection.docs,
      QuarkDrawerSection.sheets,
      QuarkDrawerSection.system,
      QuarkDrawerSection.vault,
      QuarkDrawerSection.users,
      QuarkDrawerSection.settings,
    ]) {
      expect(
        find.byKey(ValueKey('drawer_${section.name}')),
        findsOneWidget,
        reason: '${section.name} is missing',
      );
    }
    final files = tester.widget<ListTile>(
      find.byKey(const ValueKey('drawer_files')),
    );
    expect(files.selected, isTrue);
  });

  testWidgets('keeps admin-only pages out of a non-admin drawer', (
    tester,
  ) async {
    await pumpDrawer(tester);

    expect(find.byKey(const ValueKey('drawer_vault')), findsNothing);
    expect(find.byKey(const ValueKey('drawer_users')), findsNothing);
    expect(find.byKey(const ValueKey('drawer_settings')), findsOneWidget);
  });

  testWidgets('follows the admin flag while the drawer is open', (
    tester,
  ) async {
    await pumpDrawer(tester);
    expect(find.byKey(const ValueKey('drawer_vault')), findsNothing);
    expect(find.byKey(const ValueKey('drawer_users')), findsNothing);

    settings.isAdmin.value = true;
    await tester.pump();
    expect(find.byKey(const ValueKey('drawer_vault')), findsOneWidget);
    expect(find.byKey(const ValueKey('drawer_users')), findsOneWidget);

    // A demoted admin loses the entries without signing out.
    settings.isAdmin.value = false;
    await tester.pump();
    expect(find.byKey(const ValueKey('drawer_vault')), findsNothing);
    expect(find.byKey(const ValueKey('drawer_users')), findsNothing);
  });

  testWidgets('a row goes to its page', (tester) async {
    settings.isAdmin.value = true;
    await pumpDrawer(tester);

    await tester.tap(find.byKey(const ValueKey('drawer_vault')));
    await tester.pumpAndSettle();

    expect(find.text('vault page'), findsOneWidget);
    expect(find.text('files page'), findsNothing);
  });

  testWidgets('the current page closes the drawer and stays put', (
    tester,
  ) async {
    await pumpDrawer(tester);

    await tester.tap(find.byKey(const ValueKey('drawer_files')));
    await tester.pumpAndSettle();

    expect(scaffoldKey.currentState!.isDrawerOpen, isFalse);
    expect(find.text('files page'), findsOneWidget);
  });

  group('with two Quarks saved (#2230)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await settings.load();
      await settings.addHost(
        HostEntry(name: 'Home', hostAddress: 'http://home.local'),
      );
      await settings.addHost(
        HostEntry(name: 'Cabin', hostAddress: 'http://cabin.local:8443'),
      );
      await settings.setActiveIndex(settings.hosts.length - 2);
    });

    testWidgets('picking another Quark switches to it and goes through login', (
      tester,
    ) async {
      await pumpDrawer(tester);
      expect(find.text('Home'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('drawer_host_header')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('drawer_host_${settings.hosts.length - 1}')),
      );
      await tester.pumpAndSettle();

      expect(settings.activeHost, 'http://cabin.local:8443');
      expect(find.text('login page'), findsOneWidget);
    });

    testWidgets('picking the active Quark only closes the drawer', (
      tester,
    ) async {
      await pumpDrawer(tester);
      final before = settings.activeIndex;

      await tester.tap(find.byKey(const ValueKey('drawer_host_header')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('drawer_host_$before')));
      await tester.pumpAndSettle();

      expect(settings.activeIndex, before);
      expect(scaffoldKey.currentState!.isDrawerOpen, isFalse);
      expect(find.text('files page'), findsOneWidget);
    });
  });
}
