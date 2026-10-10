import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #2344: a renamed Quark stops answering to its old `.local` name, so the
/// app moves its saved address. Everything kept per host is keyed by that
/// address, and the router watches the session token, so the move has to
/// carry all of it across without the token ever reading null.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final stored = <String, String>{};

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async {
          final key = call.arguments['key'] as String?;
          switch (call.method) {
            case 'read':
              return stored[key];
            case 'write':
              stored[key!] = call.arguments['value'] as String;
              return null;
            case 'delete':
              stored.remove(key);
              return null;
            default:
              return null;
          }
        });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  final settings = AppSettings.instance;

  setUp(() async {
    stored.clear();
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {
          'name': 'Home',
          'hostAddress': 'https://quark.local',
          'remoteAddress': 'https://home.example.ts.net',
        },
        {'name': 'Other', 'hostAddress': 'https://other.local'},
      ]),
      'activeHostIndex': 0,
    });
    await settings.load();
    await settings.setSessionToken('home-token');
    await settings.setUsername('alice');
    await settings.acceptTerms();
    await settings.welcomeNewOwner();
  });

  test(
    'the address moves and the entry keeps its name and remote address',
    () async {
      await settings.moveHost('https://quark.local', 'https://kitchen.local');

      expect(settings.activeHost, 'https://kitchen.local');
      expect(settings.activeHostNotifier.value, 'https://kitchen.local');
      expect(settings.activeHostEntry?.name, 'Home');
      expect(
        settings.activeHostEntry?.remoteAddress,
        'https://home.example.ts.net',
      );
      expect(settings.hosts.map((host) => host.hostAddress), [
        'https://kitchen.local',
        'https://other.local',
      ]);
    },
  );

  test('the session, username, terms and welcome move with it', () async {
    await settings.moveHost('https://quark.local', 'https://kitchen.local');

    expect(settings.sessionToken, 'home-token');
    expect(settings.username, 'alice');
    expect(settings.hasAcceptedTerms.value, isTrue);
    expect(settings.filesWelcome.value, FilesWelcome.newOwner);
    expect(settings.sessionTokenFor('https://quark.local'), isNull);
    expect(settings.usernameFor('https://quark.local'), isNull);
    expect(settings.hasAcceptedTermsFor('https://quark.local'), isFalse);
  });

  test('the session token never reads null on the way', () async {
    final seen = <String?>[];
    void record() => seen.add(settings.sessionTokenNotifier.value);
    settings.sessionTokenNotifier.addListener(record);
    settings.activeHostNotifier.addListener(record);
    addTearDown(() {
      settings.sessionTokenNotifier.removeListener(record);
      settings.activeHostNotifier.removeListener(record);
    });

    await settings.moveHost('https://quark.local', 'https://kitchen.local');

    expect(seen, isNotEmpty);
    expect(seen, everyElement('home-token'));
  });

  test('the move survives a restart', () async {
    await settings.moveHost('https://quark.local', 'https://kitchen.local');
    await settings.load();

    expect(settings.activeHost, 'https://kitchen.local');
    expect(settings.sessionToken, 'home-token');
    expect(settings.username, 'alice');
    expect(settings.hasAcceptedTerms.value, isTrue);
    expect(settings.filesWelcome.value, FilesWelcome.newOwner);
  });

  test('an address nothing is saved under changes nothing', () async {
    await settings.moveHost('https://attic.local', 'https://kitchen.local');

    expect(settings.hosts.map((host) => host.hostAddress), [
      'https://quark.local',
      'https://other.local',
    ]);
    expect(settings.sessionToken, 'home-token');
  });

  test(
    'a Quark that is not the active one moves without taking over',
    () async {
      await settings.moveHost('https://other.local', 'https://attic.local');

      expect(settings.activeHost, 'https://quark.local');
      expect(settings.sessionToken, 'home-token');
      expect(settings.hosts[1].hostAddress, 'https://attic.local');
    },
  );
}
