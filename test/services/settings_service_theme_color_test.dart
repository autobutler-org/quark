import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/settings_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #2740: the theme color calls, and the refresh that feeds [AppSettings.themeColor].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final settings = AppSettings.instance;
  final requests = <http.Request>[];

  /// Answers each request with what [respond] returns for it, recording it.
  void answerWith(http.Response Function(http.Request request) respond) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      return respond(request);
    });
  }

  /// Answers every request with [status] and [body], recording it.
  void answer(int status, Object body) =>
      answerWith((_) => http.Response(jsonEncode(body), status));

  /// Boots [AppSettings] on one host, signed in when [signedIn].
  Future<void> load({bool signedIn = true}) async {
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'One', 'hostAddress': 'http://one.local'},
      ]),
    });
    await settings.load();
    await settings.setSessionToken(signedIn ? 'token' : null);
  }

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  setUp(requests.clear);
  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  group('the calls', () {
    setUp(load);

    test("reads the Quark's theme color without a session", () async {
      answer(200, {'themeColor': 'violet'});
      expect(await SettingsService.getQuarkThemeColor(), 'violet');
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/api/v0/settings/public');
      expect(requests.single.headers, isNot(contains('Authorization')));
    });

    test("reads the user's own theme color with the session", () async {
      answer(200, {'themeColor': ''});
      expect(await SettingsService.getMyThemeColor(), '');
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/api/v0/settings/me');
      expect(requests.single.headers['Authorization'], 'Bearer token');
    });

    test(
      "saves the user's own theme color as a lowercase storage string",
      () async {
        answer(200, {'themeColor': '#aabbcc'});
        final custom = QuarkThemeColor.fromSeed(const Color(0xFFAABBCC));
        await SettingsService.setMyThemeColor(custom.storageValue);
        expect(requests.single.method, 'PUT');
        expect(requests.single.url.path, '/api/v0/settings/me');
        expect(jsonDecode(requests.single.body), {'themeColor': '#aabbcc'});
      },
    );

    test('saves empty to follow the Quark', () async {
      answer(200, {'themeColor': ''});
      await SettingsService.setMyThemeColor('');
      expect(jsonDecode(requests.single.body), {'themeColor': ''});
    });

    test("saves the Quark's default through the admin route", () async {
      answer(200, {'themeColor': 'lime'});
      await SettingsService.setQuarkThemeColor('lime');
      expect(requests.single.method, 'PUT');
      expect(requests.single.url.path, '/api/v0/settings/theme-color');
      expect(jsonDecode(requests.single.body), {'themeColor': 'lime'});
      expect(requests.single.headers['Authorization'], 'Bearer token');
    });

    test('a refusal is an ApiException carrying the status', () async {
      answer(403, {'error': 'admin only'});
      await expectLater(
        SettingsService.setQuarkThemeColor('lime'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
      answer(400, {'error': 'invalid theme color'});
      await expectLater(
        SettingsService.setMyThemeColor('#AABBCC'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
      answer(500, {'error': 'boom'});
      await expectLater(
        SettingsService.getQuarkThemeColor(),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('refreshThemeColor', () {
    http.Response themeColors(http.Request request) => http.Response(
      jsonEncode({
        'themeColor': request.url.path.endsWith('/public') ? 'lime' : 'violet',
      }),
      200,
    );

    test('signed out, fetches only the public settings', () async {
      await load(signedIn: false);
      answerWith(themeColors);

      await SettingsService.refreshThemeColor();

      expect(requests.map((r) => r.url.path), ['/api/v0/settings/public']);
      expect(settings.quarkThemeColor.value, 'lime');
      expect(settings.userThemeColor.value, isNull);
      expect(settings.themeColor.value, QuarkThemeColor.lime);
    });

    test("signed in, the user's own theme color wins", () async {
      await load();
      answerWith(themeColors);

      await SettingsService.refreshThemeColor();

      expect(requests.map((r) => r.url.path).toSet(), {
        '/api/v0/settings/public',
        '/api/v0/settings/me',
      });
      expect(settings.quarkThemeColor.value, 'lime');
      expect(settings.userThemeColor.value, 'violet');
      expect(settings.themeColor.value, QuarkThemeColor.violet);
    });

    test('a failure keeps the theme color and does not throw', () async {
      await load();
      answerWith(themeColors);
      await SettingsService.refreshThemeColor();

      answer(500, {'error': 'boom'});
      await SettingsService.refreshThemeColor();

      expect(settings.themeColor.value, QuarkThemeColor.violet);
      expect(settings.sessionToken, 'token');
    });

    test('an unreachable Quark does not throw either', () async {
      await load(signedIn: false);
      answerWith((_) => throw http.ClientException('connection refused'));

      await SettingsService.refreshThemeColor();

      expect(settings.themeColor.value, QuarkThemeColor.classic);
    });

    test('signing out forgets the override but keeps the color', () async {
      await load();
      answerWith(themeColors);
      await SettingsService.refreshThemeColor();

      await settings.setSessionToken(null);
      await SettingsService.refreshThemeColor();

      expect(settings.userThemeColor.value, isNull);
      // The sign-in page keeps the color the user last saw on this Quark.
      expect(settings.themeColor.value, QuarkThemeColor.violet);
    });
  });
}
