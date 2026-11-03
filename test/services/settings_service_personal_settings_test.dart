import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_quark_http.dart';
import '../support/secure_storage.dart';

/// #1914: the personal preferences that follow the account across devices.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final settings = AppSettings.instance;

  /// Boots [AppSettings] on one host with this device's preferences set
  /// away from their defaults, signed in when [signedIn].
  Future<void> load({bool signedIn = true}) async {
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'One', 'hostAddress': 'http://one.local'},
      ]),
      'themeMode': 'dark',
      'refreshIntervalSeconds': 30,
      'document_editor_auto_save': false,
      'document_editor_dark_page': true,
    });
    await settings.load();
    await settings.setSessionToken(signedIn ? 'token' : null);
  }

  /// Serves `/settings/me` from [stored] the way the Quark does: a GET reads
  /// it, a PUT replaces it whole.
  void serve(Map<String, dynamic> stored) => answerWith((request) {
    if (request.method == 'PUT') {
      stored
        ..clear()
        ..addAll(jsonDecode(request.body) as Map<String, dynamic>);
    }
    return http.Response(jsonEncode(stored), 200);
  });

  setUpAll(mockSecureStorage);
  useFakeQuark();

  group('refreshPersonalSettings', () {
    test('uploads what the account lacks, once, from this device', () async {
      await load();
      final stored = <String, dynamic>{'themeColor': 'violet'};
      serve(stored);

      await SettingsService.refreshPersonalSettings();

      expect(requests.map((r) => r.method), ['GET', 'GET', 'PUT']);
      expect(stored, {
        'themeColor': 'violet',
        'themeMode': 'dark',
        'refreshIntervalSeconds': 30,
        'documentAutoSave': false,
        'documentDarkPage': true,
      });
      expect(settings.themeMode.value, ThemeMode.dark);
    });

    test('uploads only the missing ones, and applies the rest', () async {
      await load();
      final stored = <String, dynamic>{'themeMode': 'light'};
      serve(stored);

      await SettingsService.refreshPersonalSettings();

      expect(requests.where((r) => r.method == 'PUT'), hasLength(1));
      expect(stored, {
        'themeMode': 'light',
        'refreshIntervalSeconds': 30,
        'documentAutoSave': false,
        'documentDarkPage': true,
      });
      expect(settings.themeMode.value, ThemeMode.light);
    });

    test("the account's values replace this device's, with no save", () async {
      await load();
      serve({
        'themeMode': 'light',
        'refreshIntervalSeconds': 0,
        'documentAutoSave': true,
        'documentDarkPage': false,
      });

      await SettingsService.refreshPersonalSettings();

      expect(requests.map((r) => r.method), ['GET']);
      expect(settings.themeMode.value, ThemeMode.light);
      expect(settings.refreshIntervalSeconds, 0);
      expect(settings.documentAutoSave.value, true);
      expect(settings.documentDarkPage.value, false);
      // Kept on the device for the next start's first frame.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('themeMode'), 'light');
      expect(prefs.getBool('document_editor_dark_page'), false);
    });

    test('drops an answer that arrives after the session changed', () async {
      await load();
      answerWith((request) async {
        await settings.setSessionToken('other');
        return http.Response(jsonEncode({'themeMode': 'light'}), 200);
      });

      await SettingsService.refreshPersonalSettings();

      expect(requests.map((r) => r.method), ['GET']);
      expect(settings.themeMode.value, ThemeMode.dark);
    });

    test('signed out, asks nothing', () async {
      await load(signedIn: false);
      serve({});

      await SettingsService.refreshPersonalSettings();

      expect(requests, isEmpty);
    });

    test('a failure does not throw', () async {
      await load();
      answer(500, {'error': 'boom'});

      await SettingsService.refreshPersonalSettings();

      expect(settings.themeMode.value, ThemeMode.dark);
    });
  });

  group('the setters', () {
    test('signed in, save locally and merge into the account', () async {
      await load();
      final stored = <String, dynamic>{'themeColor': 'violet'};
      serve(stored);

      await SettingsService.setMyDocumentDarkPage(false);

      expect(settings.documentDarkPage.value, false);
      expect(stored, {'themeColor': 'violet', 'documentDarkPage': false});
    });

    test('signed out, save only locally', () async {
      await load(signedIn: false);
      serve({});

      await SettingsService.setMyThemeMode(ThemeMode.light);

      expect(settings.themeMode.value, ThemeMode.light);
      expect(requests, isEmpty);
    });

    test('keep the local change when the account refuses it', () async {
      await load();
      answer(500, {'error': 'boom'});

      await expectLater(
        SettingsService.setMyRefreshIntervalSeconds(60),
        throwsException,
      );
      expect(settings.refreshIntervalSeconds, 60);
      await SettingsService.logFailure(
        SettingsService.setMyDocumentAutoSave(true),
      );
      expect(settings.documentAutoSave.value, true);
    });
  });
}
