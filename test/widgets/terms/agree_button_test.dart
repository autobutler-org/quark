import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/widgets/terms/agree_button.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #2071: while terms acceptance was in flight the button's `onPressed` went
/// null, so [FilledButton] painted the disabled gray, and the label was
/// replaced by a loader alone. The control read as a blank gray button for
/// the whole round-trip.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  final settings = AppSettings.instance;

  Future<void> clearHosts() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  }

  setUp(() async {
    await clearHosts();
    authStatusProbe = AuthService.checkStatus;
  });

  tearDown(() async {
    await clearHosts();
    authStatusProbe = AuthService.checkStatus;
  });

  testWidgets('keeps a labeled primary button while acceptance is in flight', (
    tester,
  ) async {
    await settings.addHost(
      HostEntry(name: 'Quark', hostAddress: 'https://quark-2071.local'),
    );

    // The status call is the round-trip the button has to stay readable
    // through. Leave it pending so the in-flight frame is what we pump.
    final gate = Completer<AuthStatus>();
    var probes = 0;
    authStatusProbe = () {
      probes++;
      return gate.future;
    };

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: AgreeButton()),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (_, _) => const Scaffold(body: Text('login')),
        ),
        GoRoute(
          path: AppRoutes.setup,
          builder: (_, _) => const Scaffold(body: Text('setup')),
        ),
        GoRoute(
          path: AppRoutes.files,
          builder: (_, _) => const Scaffold(body: Text('files')),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(theme: QuarkTheme.light(), routerConfig: router),
    );

    expect(find.text('I Agree'), findsOneWidget);
    expect(find.text('Continuing…'), findsNothing);

    await tester.tap(find.text('I Agree'));
    await tester.pump();

    expect(find.text('Continuing…'), findsOneWidget);
    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.text('I Agree'), findsNothing);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);

    final scheme = Theme.of(
      tester.element(find.byType(FilledButton)),
    ).colorScheme;
    final materials = tester.widgetList<Material>(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.byType(Material),
      ),
    );
    expect(
      materials.any((material) => material.color == scheme.primary),
      isTrue,
    );

    // A second tap must not start another accept while the first is in flight.
    await tester.tap(find.text('Continuing…'), warnIfMissed: false);
    await tester.pump();
    expect(probes, 1);

    gate.complete(const AuthStatus(setupComplete: true));
    await tester.pump();
    await tester.pump();

    expect(find.text('login'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
