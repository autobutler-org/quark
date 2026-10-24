import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #1623: terms acceptance used to be one app-wide bool, so a user who had
/// accepted once was never asked again — even when pointing the app at a
/// different Quark they'd never seen. Acceptance is now recorded per host.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() {
    // AppSettings.load() reads the session token from secure storage on
    // native platforms; there's no plugin behind it in a unit test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  final settings = AppSettings.instance;

  String hostsJson(List<(String, String)> hosts) => jsonEncode([
    for (final (name, address) in hosts) {'name': name, 'hostAddress': address},
  ]);

  /// Boots [AppSettings] from a clean prefs store. `load()` is the only way to
  /// reset the singleton's private state between tests.
  Future<void> loadWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    await settings.load();
  }

  group('per-host acceptance', () {
    test('a freshly added host has not accepted terms', () async {
      await loadWith({
        'hosts': hostsJson([('One', 'http://one.local')]),
      });

      expect(settings.hasAcceptedTerms.value, isFalse);
    });

    test('accepting records the active host and flips the notifier', () async {
      await loadWith({
        'hosts': hostsJson([('One', 'http://one.local')]),
      });

      await settings.acceptTerms();

      expect(settings.hasAcceptedTerms.value, isTrue);
    });

    test('switching to an unaccepted host un-accepts terms', () async {
      await loadWith({
        'hosts': hostsJson([
          ('One', 'http://one.local'),
          ('Two', 'http://two.local'),
        ]),
        'activeHostIndex': 0,
      });
      await settings.acceptTerms();
      expect(settings.hasAcceptedTerms.value, isTrue);

      await settings.setActiveIndex(1);

      expect(settings.hasAcceptedTerms.value, isFalse);
    });

    test('switching back to an accepted host re-accepts', () async {
      await loadWith({
        'hosts': hostsJson([
          ('One', 'http://one.local'),
          ('Two', 'http://two.local'),
        ]),
        'activeHostIndex': 0,
      });
      await settings.acceptTerms();
      await settings.setActiveIndex(1);
      expect(settings.hasAcceptedTerms.value, isFalse);

      await settings.setActiveIndex(0);

      expect(settings.hasAcceptedTerms.value, isTrue);
    });

    // The scenario that surfaced this: retyping the URL of the host you're on
    // points the app at a Quark you've never accepted terms for.
    test('editing the active host address un-accepts terms', () async {
      await loadWith({
        'hosts': hostsJson([('One', 'http://one.local')]),
      });
      await settings.acceptTerms();

      await settings.updateHost(
        0,
        HostEntry(name: 'One', hostAddress: 'http://somewhere-else.local'),
      );

      expect(settings.hasAcceptedTerms.value, isFalse);
    });

    test('editing only the display name keeps the acceptance', () async {
      await loadWith({
        'hosts': hostsJson([('One', 'http://one.local')]),
      });
      await settings.acceptTerms();

      await settings.updateHost(
        0,
        HostEntry(name: 'Renamed', hostAddress: 'http://one.local'),
      );

      expect(settings.hasAcceptedTerms.value, isTrue);
    });

    test('acceptance survives a restart', () async {
      await loadWith({
        'hosts': hostsJson([('One', 'http://one.local')]),
      });
      await settings.acceptTerms();

      // Same backing store, fresh load — SharedPreferences keeps what was
      // written above.
      await settings.load();

      expect(settings.hasAcceptedTerms.value, isTrue);
    });

    test('case and trailing slashes do not create a second host', () async {
      await loadWith({
        'hosts': hostsJson([('One', 'http://one.local')]),
      });
      await settings.acceptTerms();

      await settings.updateHost(
        0,
        HostEntry(name: 'One', hostAddress: 'http://One.local/'),
      );

      expect(settings.hasAcceptedTerms.value, isTrue);
    });

    test('acceptTerms is a no-op with no host configured', () async {
      await loadWith({
        'hosts': hostsJson([('One', 'http://one.local')]),
      });
      await settings.removeHost(0);
      expect(settings.activeHost, isNull);

      await settings.acceptTerms();

      expect(settings.hasAcceptedTerms.value, isFalse);
    });
  });

  group('migration from the app-wide bool', () {
    test('an existing acceptance carries over to the active host', () async {
      await loadWith({
        'hosts': hostsJson([('One', 'http://one.local')]),
        'hasAcceptedTerms': true,
      });

      expect(settings.hasAcceptedTerms.value, isTrue);
    });

    test('it does not carry over to other hosts', () async {
      await loadWith({
        'hosts': hostsJson([
          ('One', 'http://one.local'),
          ('Two', 'http://two.local'),
        ]),
        'activeHostIndex': 0,
        'hasAcceptedTerms': true,
      });

      await settings.setActiveIndex(1);

      expect(settings.hasAcceptedTerms.value, isFalse);
    });

    test('it runs once and does not resurrect a later un-acceptance', () async {
      await loadWith({
        'hosts': hostsJson([('One', 'http://one.local')]),
        'hasAcceptedTerms': true,
      });
      expect(settings.hasAcceptedTerms.value, isTrue);

      // Point at a Quark the user never accepted, then restart. The legacy
      // bool must not re-grant acceptance for the new address.
      await settings.updateHost(
        0,
        HostEntry(name: 'One', hostAddress: 'http://two.local'),
      );
      await settings.load();

      expect(settings.hasAcceptedTerms.value, isFalse);
    });

    test('a legacy false does not accept anything', () async {
      await loadWith({
        'hosts': hostsJson([('One', 'http://one.local')]),
        'hasAcceptedTerms': false,
      });

      expect(settings.hasAcceptedTerms.value, isFalse);
    });
  });
}
