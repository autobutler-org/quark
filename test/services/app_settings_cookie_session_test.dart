import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/users_service.dart';
import 'package:quark/utils/session_cookie.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secure_storage.dart';

/// A Quark that answers every request with an empty 200, and remembers what
/// it was asked.
class _RecordingClient extends http.BaseClient {
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode('{}')),
      200,
      request: request,
    );
  }
}

class _Service with AuthenticatedService {}

/// #2156: the web build served by the Quark keeps its session in the Quark's
/// HttpOnly cookie, so the token is never held or persisted where a script on
/// the page could read it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Where the token store lands under `flutter test`, which is never web.
  final stored = <String, String>{};

  setUpAll(() {
    mockSecureStorage(stored);
  });

  final settings = AppSettings.instance;
  const cookieHost = 'http://one.local';
  const bearerHost = 'http://two.local';
  final defaultUsesCookieSession = usesCookieSession;

  /// Everything either store holds, for asserting a token is in neither.
  Future<String> persisted() async {
    final prefs = await SharedPreferences.getInstance();
    return [
      ...stored.values,
      for (final key in prefs.getKeys()) '${prefs.get(key)}',
    ].join('\n');
  }

  Future<void> load() async {
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'One', 'hostAddress': cookieHost},
        {'name': 'Two', 'hostAddress': bearerHost},
      ]),
      'activeHostIndex': 0,
    });
    await settings.load();
  }

  setUp(() {
    stored.clear();
    usesCookieSession = (host) => host == cookieHost;
  });

  tearDown(() {
    usesCookieSession = defaultUsesCookieSession;
    authHttpClientFactory = () => sharedHttpClient;
  });

  test('off the web no host is a cookie session', () {
    expect(defaultUsesCookieSession('/'), isFalse);
  });

  group('a cookie-session host', () {
    test('is signed in without holding or persisting the token', () async {
      await load();
      await settings.setSessionToken('real');

      expect(settings.sessionToken, cookieSessionMarker);
      expect(settings.sessionTokenNotifier.value, isNotNull);
      expect(settings.bearerToken, isNull);
      expect(jsonDecode(stored['session_token']!), {
        cookieHost: cookieSessionMarker,
      });
      expect(await persisted(), isNot(contains('real')));
    });

    test('signs out when the token is cleared', () async {
      await load();
      await settings.setSessionToken('real');
      await settings.setSessionToken(null);

      expect(settings.sessionToken, isNull);
      expect(settings.sessionTokenNotifier.value, isNull);
      expect(jsonDecode(stored['session_token']!), isEmpty);
    });

    test('load replaces a token an earlier build persisted', () async {
      stored['session_token'] = jsonEncode({
        cookieHost: 'real',
        bearerHost: 'two-token',
      });

      await load();

      expect(settings.sessionToken, cookieSessionMarker);
      expect(settings.bearerToken, isNull);
      expect(jsonDecode(stored['session_token']!), {
        cookieHost: cookieSessionMarker,
        bearerHost: 'two-token',
      });
    });

    test('load replaces a pre-#1645 bare token too', () async {
      stored['session_token'] = 'real';

      await load();

      expect(settings.sessionToken, cookieSessionMarker);
      expect(await persisted(), isNot(contains('real')));
    });

    test('sends no Authorization header', () async {
      await load();
      await settings.setSessionToken('real');

      expect(_Service().authHeaders, isEmpty);
    });

    test('builds media and avatar URLs with no token', () async {
      await load();
      await settings.setSessionToken('real');

      final urls = [
        FilesService.constructMediaUrl('a.mp4'),
        FilesService.constructThumbnailUrl('a.jpg', size: 'small'),
        UsersService.avatarUrl(1, version: 2),
      ];
      for (final url in urls) {
        expect(url.queryParameters, isNot(contains('token')), reason: '$url');
      }
    });

    test('logout still tells the Quark, with no Authorization', () async {
      await load();
      await settings.setSessionToken('real');
      final client = _RecordingClient();
      authHttpClientFactory = () => client;

      await AuthService.logout();

      expect(settings.sessionToken, isNull);
      final request = client.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v0/auth/logout');
      expect(request.headers, isNot(contains('Authorization')));
      expect(request.headers, isNot(contains('authorization')));
    });

    test('auth status is asked with no Authorization', () async {
      await load();
      await settings.setSessionToken('real');
      final client = _RecordingClient();
      authHttpClientFactory = () => client;

      await AuthService.checkStatus();

      expect(
        client.requests.single.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
    });
  });

  group('any other host', () {
    Future<void> signIn() async {
      await load();
      await settings.setActiveIndex(1);
      await settings.setSessionToken('two-token');
    }

    test('keeps and persists the token as before', () async {
      await signIn();

      expect(settings.sessionToken, 'two-token');
      expect(settings.bearerToken, 'two-token');
      expect(jsonDecode(stored['session_token']!), {bearerHost: 'two-token'});
    });

    test('sends the token as a Bearer', () async {
      await signIn();

      expect(_Service().authHeaders, {'Authorization': 'Bearer two-token'});
      expect(
        FilesService.constructMediaUrl('a.mp4').queryParameters['token'],
        'two-token',
      );
    });

    test('logout sends the token it is ending', () async {
      await signIn();
      final client = _RecordingClient();
      authHttpClientFactory = () => client;

      await AuthService.logout();

      expect(
        client.requests.single.headers['Authorization'],
        'Bearer two-token',
      );
    });

    test('signed out, logout sends nothing', () async {
      await load();
      final client = _RecordingClient();
      authHttpClientFactory = () => client;

      await AuthService.logout();

      expect(client.requests, isEmpty);
    });
  });
}
