import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/settings_page.dart';
import 'package:quark/services/app_settings.dart';

import '../support/unreachable_quark.dart';

/// #1762: App Store Review Guideline 5.1.1(v) rejects an app that supports
/// account creation without letting a user start deleting their account from
/// inside it — and rejects one where a reviewer cannot find the control. It
/// lives in Settings, in the Account section, under Sign out.
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

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  final entry = find.byKey(const ValueKey('settings_delete_account'));
  final resetEntry = find.byKey(const ValueKey('settings_reset_quark'));

  testWidgets('offers deletion next to sign out', (tester) async {
    await signIn();

    await pumpSettings(tester);

    expect(entry, findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
    // The reviewer's path: Settings, Account, under Sign out.
    expect(
      tester.getTopLeft(entry).dy,
      greaterThan(tester.getTopLeft(find.text('Sign out')).dy),
    );
  });

  testWidgets('keeps the reset in its own section, below', (tester) async {
    await signIn();

    await pumpSettings(tester);

    // Two intents, two entries, under two headings. Nothing here reads as a
    // way to reset the appliance by deleting an account.
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

  testWidgets('offers neither without a session', (tester) async {
    await pumpSettings(tester);

    expect(entry, findsNothing);
    expect(resetEntry, findsNothing);
  });

  // #1899: resetting the appliance is admin-only on the Quark, so a member
  // keeps their own account deletion and never sees the reset.
  testWidgets('offers a non-admin deletion but no reset', (tester) async {
    await signIn();
    settings.isAdmin.value = false;

    await pumpSettings(tester);

    expect(entry, findsOneWidget);
    expect(resetEntry, findsNothing);
    expect(find.text('Reset'), findsNothing);
  });

  testWidgets('asks for the username before anything is deleted', (
    tester,
  ) async {
    await signIn();
    await pumpSettings(tester);

    await tester.tap(entry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey('delete_account_confirm_field')),
      findsOneWidget,
    );
    // Nothing can be sent until the username is typed.
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('delete_account_submit')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('asks for the username before anything is reset', (tester) async {
    await signIn();
    await pumpSettings(tester);

    await tester.scrollUntilVisible(resetEntry, 200);
    await tester.tap(resetEntry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey('reset_quark_confirm_field')),
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
