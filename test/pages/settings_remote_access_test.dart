import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/settings_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/remote_access_config.dart';

import '../support/unreachable_quark.dart';

/// #1815: remote access being switched on and the node being on the tailnet
/// are separate facts, and the section shows which one the Quark is in.
/// #2857: setup is a sheet, and turning it off for everyone is confirmed.
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
  });

  tearDown(() async {
    HttpOverrides.global = priorOverrides;
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
    await reset();
  });

  /// How many times the page has read the remote-access status.
  var statusReads = 0;

  /// The non-GET requests the page sent to the remote-access route.
  final changes = <String>[];

  /// Answers the remote-access status with [status], read afresh on every
  /// request so a test can change it mid-flight; every other section's
  /// request gets a 404 it can fail on.
  ///
  /// Signs in as an admin unless [isAdmin] is false: turning remote access on
  /// and off is admin-only (#1899).
  Future<void> pumpWithStatus(
    WidgetTester tester,
    Map<String, dynamic> status, {
    bool isAdmin = true,
  }) async {
    statusReads = 0;
    changes.clear();
    sharedHttpClientFactory = () => MockClient((request) async {
      if (request.url.path != '/api/v0/settings/remote-access') {
        return http.Response('', 404);
      }
      switch (request.method) {
        case 'POST':
          changes.add('POST');
          status['enabled'] = true;
        case 'DELETE':
          changes.add('DELETE');
          status
            ..['enabled'] = false
            ..['connected'] = false
            ..remove('error');
        default:
          statusReads++;
      }
      return http.Response(jsonEncode(status), 200);
    });
    await settings.addHost(
      HostEntry(name: 'Quark', hostAddress: 'https://quark.local'),
    );
    await settings.setSessionToken('a-session');
    settings.isAdmin.value = isAdmin;

    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Settings overflows its own app bar at any viewport; ignore only that.
    final priorOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = priorOnError);
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      priorOnError?.call(details);
    };

    await tester.pumpWidget(
      const MaterialApp(home: SettingsPage(tab: SettingsTab.network)),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Lets the page's loaders and polls run without settling: a loader on
  /// screen never stops animating.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  // #2358: the Quark enrolls itself as its own household, so an admin is
  // offered setup. Release builds say Coming soon instead (#2857); tests run
  // a debug build.
  testWidgets('offers an admin setup', (tester) async {
    await pumpWithStatus(tester, {'enabled': false, 'connected': false});

    expect(find.byKey(const ValueKey('remote_access_set_up')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('remote_access_coming_soon')),
      findsNothing,
    );
    expect(find.text('Coming soon'), findsNothing);
  });

  testWidgets('tells a non-admin who can turn it on', (tester) async {
    await pumpWithStatus(tester, {
      'enabled': false,
      'connected': false,
    }, isAdmin: false);

    expect(find.byKey(const ValueKey('remote_access_set_up')), findsNothing);
    expect(
      find.byKey(const ValueKey('remote_access_member_note')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('remote_access_coming_soon')),
      findsNothing,
    );
  });

  testWidgets('offers a non-admin no way to turn it off', (tester) async {
    await pumpWithStatus(tester, {
      'enabled': true,
      'connected': true,
    }, isAdmin: false);

    expect(
      find.byKey(const ValueKey('remote_access_status_on')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Switch>(find.byKey(const ValueKey('remote_access_switch')))
          .onChanged,
      isNull,
    );
  });

  testWidgets('shows connecting while on but not on the tailnet', (
    tester,
  ) async {
    await pumpWithStatus(tester, {'enabled': true, 'connected': false});

    expect(find.text('Connecting…'), findsOneWidget);
    expect(find.byKey(const ValueKey('remote_access_status_on')), findsNothing);
    expect(find.byKey(const ValueKey('remote_access_switch')), findsOneWidget);
  });

  testWidgets('shows a failed start without its diagnostic', (tester) async {
    await pumpWithStatus(tester, {
      'enabled': true,
      'connected': false,
      'error': 'failed to start tsnet: listen tcp: address in use',
    });

    expect(find.text(Errors.remoteAccessFailing), findsOneWidget);
    expect(find.text(Errors.remoteAccessFailingSteps.first), findsOneWidget);
    expect(find.textContaining('tsnet'), findsNothing);
    expect(find.text('Connecting…'), findsNothing);
    expect(
      find.byKey(const ValueKey('remote_access_try_again')),
      findsOneWidget,
    );
  });

  testWidgets('Try again turns it on again', (tester) async {
    await pumpWithStatus(tester, {
      'enabled': true,
      'connected': false,
      'error': 'failed to start tsnet',
    });

    await tester.ensureVisible(
      find.byKey(const ValueKey('remote_access_try_again')),
    );
    await tester.tap(find.byKey(const ValueKey('remote_access_try_again')));
    await settle(tester);

    expect(changes, ['POST']);
  });

  // #2857: the address is for the app's own routing (#1880), not for people.
  testWidgets('says it is on, without the address, once connected', (
    tester,
  ) async {
    await pumpWithStatus(tester, {
      'enabled': true,
      'connected': true,
      'remoteUrl': 'http://100.64.0.7:80',
    });

    expect(
      find.byKey(const ValueKey('remote_access_status_on')),
      findsOneWidget,
    );
    expect(find.text('Reachable away from home'), findsOneWidget);
    expect(find.text('http://100.64.0.7:80'), findsNothing);
  });

  testWidgets('polls while connecting and stops once connected', (
    tester,
  ) async {
    final status = <String, dynamic>{'enabled': true, 'connected': false};
    await pumpWithStatus(tester, status);
    expect(find.text('Connecting…'), findsOneWidget);

    status
      ..['connected'] = true
      ..['remoteUrl'] = 'http://100.64.0.7:80';
    await tester.pump(RemoteAccessConfig.statusPollInterval);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('remote_access_status_on')),
      findsOneWidget,
    );

    final readsWhenConnected = statusReads;
    await tester.pump(RemoteAccessConfig.statusPollInterval * 3);
    expect(statusReads, readsWhenConnected);
  });

  testWidgets('does not poll while remote access is off', (tester) async {
    await pumpWithStatus(tester, {'enabled': false, 'connected': false});

    final reads = statusReads;
    await tester.pump(RemoteAccessConfig.statusPollInterval * 3);
    expect(statusReads, reads);
  });

  testWidgets('the setup sheet follows the Quark from intro to done', (
    tester,
  ) async {
    final status = <String, dynamic>{'enabled': false, 'connected': false};
    await pumpWithStatus(tester, status);

    await tester.tap(find.byKey(const ValueKey('remote_access_set_up')));
    await settle(tester);
    expect(find.text('Turn on remote access'), findsWidgets);

    await tester.ensureVisible(
      find.byKey(const ValueKey('remote_access_setup_turn_on')),
    );
    await tester.tap(find.byKey(const ValueKey('remote_access_setup_turn_on')));
    await settle(tester);
    expect(changes, ['POST']);
    expect(find.text('Setting up remote access'), findsOneWidget);

    status['connected'] = true;
    await tester.pump(RemoteAccessConfig.statusPollInterval);
    await settle(tester);
    expect(
      find.byKey(const ValueKey('remote_access_setup_done')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('remote_access_setup_done')));
    await settle(tester);
    expect(
      find.byKey(const ValueKey('remote_access_setup_done')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('remote_access_status_on')),
      findsOneWidget,
    );
  });

  testWidgets('the setup sheet closes on a failure', (tester) async {
    final status = <String, dynamic>{'enabled': false, 'connected': false};
    await pumpWithStatus(tester, status);

    await tester.tap(find.byKey(const ValueKey('remote_access_set_up')));
    await settle(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('remote_access_setup_turn_on')),
    );
    await tester.tap(find.byKey(const ValueKey('remote_access_setup_turn_on')));
    await settle(tester);

    status['error'] = 'tsnet: key rejected';
    await tester.pump(RemoteAccessConfig.statusPollInterval);
    await settle(tester);

    expect(find.text('Setting up remote access'), findsNothing);
    expect(find.text(Errors.remoteAccessFailing), findsOneWidget);
  });

  testWidgets('turning it off is confirmed first', (tester) async {
    await pumpWithStatus(tester, {'enabled': true, 'connected': true});

    await tester.tap(find.byKey(const ValueKey('remote_access_switch')));
    await settle(tester);
    expect(find.text('Turn off remote access for everyone?'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('remote_access_turn_off_cancel')),
    );
    await settle(tester);
    expect(changes, isEmpty);
    expect(
      find.byKey(const ValueKey('remote_access_status_on')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('remote_access_switch')));
    await settle(tester);
    await tester.tap(
      find.byKey(const ValueKey('remote_access_turn_off_confirm')),
    );
    await settle(tester);
    expect(changes, ['DELETE']);
    expect(find.byKey(const ValueKey('remote_access_set_up')), findsOneWidget);
  });
}
