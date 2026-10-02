import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #2022: Files greets a new owner with a card that stays until dismissed,
/// and greets an explicit sign-in once. The first is a persisted per-host
/// flag; the second lives in memory, so a reload on a stored session greets
/// nobody.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  final settings = AppSettings.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'One', 'hostAddress': 'http://one.local'},
        {'name': 'Two', 'hostAddress': 'http://two.local'},
      ]),
      'activeHostIndex': 0,
    });
    await settings.load();
  });

  tearDown(() => authHttpClientFactory = () => sharedHttpClient);

  test('nobody is greeted on a plain launch', () {
    expect(settings.filesWelcome.value, FilesWelcome.none);
  });

  group('a new owner', () {
    test('is owed the card until it is dismissed, across reloads', () async {
      await settings.welcomeNewOwner();
      expect(settings.filesWelcome.value, FilesWelcome.newOwner);

      await settings.load();
      expect(settings.filesWelcome.value, FilesWelcome.newOwner);

      await settings.dismissFilesWelcome();
      expect(settings.filesWelcome.value, FilesWelcome.none);

      await settings.load();
      expect(settings.filesWelcome.value, FilesWelcome.none);
    });

    test('is welcomed on that Quark only', () async {
      await settings.welcomeNewOwner();

      await settings.setActiveIndex(1);
      expect(settings.filesWelcome.value, FilesWelcome.none);

      await settings.setActiveIndex(0);
      expect(settings.filesWelcome.value, FilesWelcome.newOwner);
    });

    test('is forgotten with the Quark', () async {
      await settings.welcomeNewOwner();
      await settings.removeHost(0);
      await settings.addHost(
        HostEntry(name: 'One', hostAddress: 'http://one.local'),
      );

      expect(settings.filesWelcome.value, FilesWelcome.none);
      await settings.load();
      expect(settings.filesWelcome.value, FilesWelcome.none);
    });

    test('keeps the card through a later sign-in', () async {
      await settings.welcomeNewOwner();
      settings.greetSignIn();

      expect(settings.filesWelcome.value, FilesWelcome.newOwner);
    });
  });

  group('an explicit sign-in', () {
    test('is greeted until a reload', () async {
      settings.greetSignIn();
      expect(settings.filesWelcome.value, FilesWelcome.signedIn);

      await settings.load();
      expect(settings.filesWelcome.value, FilesWelcome.none);
    });

    test('is greeted on that Quark only, and can be dismissed', () async {
      settings.greetSignIn();

      await settings.setActiveIndex(1);
      expect(settings.filesWelcome.value, FilesWelcome.none);

      await settings.setActiveIndex(0);
      expect(settings.filesWelcome.value, FilesWelcome.signedIn);

      await settings.dismissFilesWelcome();
      expect(settings.filesWelcome.value, FilesWelcome.none);
    });

    test(
      'AuthService.login asks for the greeting, name already stored',
      () async {
        authHttpClientFactory = () => MockClient(
          (_) async => http.Response(jsonEncode({'token': 'plain-token'}), 200),
        );
        String? nameWhenGreeted;
        void record() {
          if (settings.filesWelcome.value == FilesWelcome.signedIn) {
            nameWhenGreeted = settings.username;
          }
        }

        settings.filesWelcome.addListener(record);
        addTearDown(() => settings.filesWelcome.removeListener(record));

        await AuthService.login(username: 'bob', password: 'hunter2hunter2');

        expect(settings.filesWelcome.value, FilesWelcome.signedIn);
        expect(nameWhenGreeted, 'bob');
      },
    );

    test(
      'a first sign-in is not greeted until its phrase is accepted',
      () async {
        authHttpClientFactory = () => MockClient(
          (_) async => http.Response(
            jsonEncode({'token': 't', 'recoveryPhrase': 'apple banana cherry'}),
            200,
          ),
        );

        final result = await AuthService.login(
          username: 'bob',
          password: 'hunter2hunter2',
        );
        expect(settings.filesWelcome.value, FilesWelcome.none);

        await AuthService.acceptSession(result);
        expect(settings.filesWelcome.value, FilesWelcome.signedIn);
      },
    );
  });
}
