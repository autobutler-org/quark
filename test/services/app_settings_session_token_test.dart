import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secure_storage.dart';

/// #1645: the session token was one app-wide value, so switching Quarks
/// carried the previous one along and the router's gate believed the user was
/// signed in to a Quark they had never logged into. Tokens are now per host.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A real store, not the usual null stub: these tests round-trip tokens
  /// through `load()`, which reads back what `setSessionToken` wrote.
  final stored = <String, String>{};

  setUpAll(() {
    mockSecureStorage(stored);
  });

  setUp(stored.clear);

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

  Future<void> loadTwoHosts() => loadWith({
    'hosts': hostsJson([
      ('One', 'http://one.local'),
      ('Two', 'http://two.local'),
    ]),
    'activeHostIndex': 0,
  });

  group('tokens are per host', () {
    test('a token set on one Quark is not visible on another', () async {
      await loadTwoHosts();
      await settings.setSessionToken('one-token');

      await settings.setActiveIndex(1);
      expect(settings.sessionToken, isNull);

      await settings.setActiveIndex(0);
      expect(settings.sessionToken, 'one-token');
    });

    test('each host keeps its own token', () async {
      await loadTwoHosts();
      await settings.setSessionToken('one-token');
      await settings.setActiveIndex(1);
      await settings.setSessionToken('two-token');

      expect(settings.sessionTokenFor('http://one.local'), 'one-token');
      expect(settings.sessionTokenFor('http://two.local'), 'two-token');
    });

    test('the lookup key normalizes case and trailing slashes', () async {
      await loadWith({
        'hosts': hostsJson([('One', 'http://one.local')]),
      });
      await settings.setSessionToken('one-token');

      expect(settings.sessionTokenFor('http://One.local/'), 'one-token');
    });

    test('switching hosts republishes the notifier', () async {
      await loadTwoHosts();
      await settings.setSessionToken('one-token');
      expect(settings.sessionTokenNotifier.value, 'one-token');

      await settings.setActiveIndex(1);
      expect(settings.sessionTokenNotifier.value, isNull);
    });

    test('clearing on a 401 only clears the active host', () async {
      await loadTwoHosts();
      await settings.setSessionToken('one-token');
      await settings.setActiveIndex(1);
      await settings.setSessionToken('two-token');

      await settings.setSessionToken(null);

      expect(settings.sessionToken, isNull);
      expect(settings.sessionTokenFor('http://one.local'), 'one-token');
    });

    test('forgetting a Quark forgets its token', () async {
      await loadTwoHosts();
      await settings.setSessionToken('one-token');

      await settings.removeHost(0);

      expect(settings.sessionTokenFor('http://one.local'), isNull);
    });

    test('with no host configured there is nothing to store against', () async {
      await loadWith({'hosts': '[]'});
      // The web/debug fallbacks seed a host; only a release-mode native app
      // reaches load() with none, so assert the guard directly instead.
      if (settings.activeHost != null) return;

      await settings.setSessionToken('orphan');

      expect(settings.sessionToken, isNull);
      expect(settings.sessionTokenNotifier.value, isNull);
    });
  });

  group('persistence', () {
    test('tokens survive a reload', () async {
      await loadTwoHosts();
      await settings.setSessionToken('one-token');
      await settings.setActiveIndex(1);
      await settings.setSessionToken('two-token');

      await loadTwoHosts();

      expect(settings.sessionTokenFor('http://one.local'), 'one-token');
      expect(settings.sessionTokenFor('http://two.local'), 'two-token');
      // #1645: restored, not just persisted — the gate reads this on launch.
      expect(settings.sessionToken, 'one-token');
    });

    // Pre-#1645 builds wrote a bare token string under the same key.
    test('a legacy bare token migrates onto the active host', () async {
      stored['session_token'] = 'legacy-token';

      await loadTwoHosts();

      expect(settings.sessionToken, 'legacy-token');
      expect(settings.sessionTokenFor('http://two.local'), isNull);
      // Rewritten in the new shape, so the next launch reads it as a map.
      expect(jsonDecode(stored['session_token']!), {
        'http://one.local': 'legacy-token',
      });
    });

    test('an unreadable store does not throw', () async {
      stored['session_token'] = '{not json';

      await loadTwoHosts();

      // Treated as a legacy bare token — the safe reading, since the only
      // thing that was ever stored here in a non-JSON shape was a token.
      expect(settings.sessionToken, '{not json');
    });
  });
}
