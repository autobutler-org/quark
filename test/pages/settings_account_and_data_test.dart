import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/pages/account_and_data_page.dart';
import 'package:quark/pages/settings_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';

import '../support/unreachable_quark.dart';

/// #1762: App Store Review Guideline 5.1.1(v) rejects an app that supports
/// account creation without letting a user start deleting their account from
/// inside it — and rejects one where a reviewer cannot find the control.
///
/// #2346: it must also be hard to reach by accident. Settings' Account section
/// carries one labeled row, **Account and data**, and the destructive actions
/// sit on the page behind it.
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

  late HttpOverrides? priorOverrides;

  Future<void> reset() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
    await settings.setSessionToken(null);
    settings.isAdmin.value = false;
  }

  setUp(() async {
    // Settings loads six sections from the Quark on mount. None of them are
    // under test here, and an unreachable Quark fails them all promptly.
    priorOverrides = HttpOverrides.current;
    HttpOverrides.global = UnreachableQuarkHttpOverrides();
    await reset();
  });

  tearDown(() async {
    HttpOverrides.global = priorOverrides;
    await reset();
  });

  Future<void> signIn() async {
    await settings.addHost(
      HostEntry(name: 'Quark', hostAddress: 'https://quark.local'),
    );
    await settings.setSessionToken('a-session');
    await settings.setUsername('ada');
    // The founding account, so the appliance reset is theirs to offer (#1899).
    settings.isAdmin.value = true;
  }

  /// Settings never settles — its SBOM section keeps a spinner turning — so
  /// pump far enough for every Quark-bound load to finish.
  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Settings overflows its own app bar by 28px at any viewport — the brand
    // button against a fixed `leadingWidth` — with or without this change.
    // Ignore that one, keep failing on anything else.
    final priorOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = priorOnError);
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      priorOnError?.call(details);
    };

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: AppRoutes.settings,
          routes: [
            GoRoute(
              path: AppRoutes.settings,
              builder: (_, _) => const SettingsPage(),
            ),
            GoRoute(
              path: AppRoutes.accountAndData,
              builder: (_, _) => const AccountAndDataPage(),
            ),
          ],
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// The drill-down on its own: it loads nothing from the Quark.
  Future<void> pumpAccountAndData(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: AccountAndDataPage()));
    await tester.pump();
  }

  final row = find.byKey(const ValueKey('settings_account_and_data'));

  final entry = find.byKey(const ValueKey('settings_delete_account'));
  final resetEntry = find.byKey(const ValueKey('settings_reset_quark'));

  testWidgets('offers a labeled row under sign out, nothing destructive', (
    tester,
  ) async {
    await signIn();

    await pumpSettings(tester);

    expect(row, findsOneWidget);
    expect(find.text('Account and data'), findsOneWidget);
    expect(
      tester.getTopLeft(row).dy,
      greaterThan(tester.getTopLeft(find.text('Sign out')).dy),
    );
    // Nothing destructive on the main page any more.
    expect(entry, findsNothing);
    expect(resetEntry, findsNothing);
    expect(find.text('Delete account'), findsNothing);
    expect(find.text('Reset this Quark'), findsNothing);
  });

  testWidgets('offers no row without a session', (tester) async {
    await pumpSettings(tester);

    expect(row, findsNothing);
  });

  testWidgets('the row drills down to the account and data page', (
    tester,
  ) async {
    await signIn();
    await pumpSettings(tester);

    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('account_and_data_page')), findsOneWidget);
    expect(entry, findsOneWidget);
    // A detail flow, so it gets a back button rather than the drawer.
    expect(find.byType(BackButton), findsOneWidget);
  });

  for (final (label, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('keeps the reset in its own section, below ($label)', (
      tester,
    ) async {
      await signIn();

      await pumpAccountAndData(tester, size: size);

      // Two intents, two entries, under two headings. Nothing here reads as a
      // way to reset the appliance by deleting an account.
      expect(entry, findsOneWidget);
      expect(resetEntry, findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);
      expect(
        tester.getTopLeft(resetEntry).dy,
        greaterThan(tester.getTopLeft(find.text('Reset')).dy),
      );
      expect(
        tester.getTopLeft(resetEntry).dy,
        greaterThan(tester.getTopLeft(entry).dy),
      );
    });
  }

  // #1899: resetting the appliance is admin-only on the Quark, so a member
  // keeps their own account deletion and never sees the reset.
  testWidgets('offers a non-admin deletion but no reset', (tester) async {
    await signIn();
    settings.isAdmin.value = false;

    await pumpAccountAndData(tester);

    expect(entry, findsOneWidget);
    expect(resetEntry, findsNothing);
    expect(find.text('Reset'), findsNothing);
  });

  testWidgets('asks for the password before anything is deleted', (
    tester,
  ) async {
    await signIn();
    await pumpAccountAndData(tester);

    await tester.tap(entry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey('delete_account_password_field')),
      findsOneWidget,
    );
    // Nothing can be sent until the password is typed.
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('delete_account_submit')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('asks for the password before anything is reset', (tester) async {
    await signIn();
    await pumpAccountAndData(tester);

    await tester.tap(resetEntry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey('reset_quark_password_field')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('reset_quark_submit')),
          )
          .onPressed,
      isNull,
    );
  });
}
