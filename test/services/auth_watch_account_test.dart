import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/events_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'events_service_test.dart' show FakeChannel, connectLocalTrustWsDefault;
import '../support/secure_storage.dart';

/// #3209: every app load asked the Quark for `/auth/status` and the account's
/// settings twice, once from [AuthService.watchAccount] itself and once more
/// when the events socket first opened. Only a reconnect may ask again.
///
/// #3465: that also dropped the one recovery a failed start-up call had. The
/// first open is not a reconnect, but it is the chance to try `/auth/status`
/// once more so [AppSettings.isAdmin] can still become true.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AuthService.stopWatchingAccount();
    EventsService.instance.stop();
    EventsService.connectChannel = connectLocalTrustWsDefault;
    authHttpClientFactory = () => sharedHttpClient;
    sharedHttpClientFactory = buildLocalTrustHttpClient;
    resetSharedHttpClient();
    AppSettings.instance.isAdmin.value = false;
  });

  testWidgets('loads the account once per start, again per reconnect', (
    tester,
  ) async {
    mockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings.instance;
    await settings.load();
    await settings.addHost(
      HostEntry(name: 'Quark', hostAddress: 'https://quark.local'),
    );
    await settings.setSessionToken('a-token');

    var statusCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v0/auth/status') statusCalls++;
      return http.Response('{"setup": true}', 200);
    });
    authHttpClientFactory = () => client;
    sharedHttpClientFactory = () => client;
    resetSharedHttpClient();
    final channels = <FakeChannel>[];
    EventsService.connectChannel = (uri, {headers}) {
      final channel = FakeChannel();
      channels.add(channel);
      return channel;
    };

    AuthService.watchAccount();
    await tester.pump(const Duration(seconds: 1));
    expect(channels, hasLength(1), reason: 'the socket opened');
    expect(statusCalls, 1);

    channels.last.closeFromServer();
    await tester.pump(const Duration(seconds: 2));
    expect(channels, hasLength(2), reason: 'the socket came back');
    expect(statusCalls, 2);

    EventsService.instance.stop();
  });

  // #3465: Vault and Users stay hidden for the session when the one start-up
  // /auth/status fails, because isAdmin is not persisted and nothing asks
  // again until a reconnect or a session change.
  testWidgets('a failed start-up status call retries without a reconnect', (
    tester,
  ) async {
    mockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings.instance;
    await settings.load();
    await settings.addHost(
      HostEntry(name: 'Quark', hostAddress: 'https://quark.local'),
    );
    await settings.setSessionToken('a-token');
    settings.isAdmin.value = false;
    final token = settings.sessionToken;

    final firstStatus = Completer<http.Response>();
    addTearDown(() {
      if (!firstStatus.isCompleted) {
        firstStatus.complete(http.Response('unavailable', 503));
      }
    });
    var statusCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path != '/api/v0/auth/status') {
        return http.Response('{"setup": true}', 200);
      }
      statusCalls++;
      if (statusCalls == 1) return firstStatus.future;
      return http.Response('{"setup": true, "isAdmin": true}', 200);
    });
    authHttpClientFactory = () => client;
    sharedHttpClientFactory = () => client;
    resetSharedHttpClient();
    final channels = <FakeChannel>[];
    EventsService.connectChannel = (uri, {headers}) {
      final channel = FakeChannel();
      channels.add(channel);
      return channel;
    };

    AuthService.watchAccount();
    await tester.pump();
    expect(channels, hasLength(1), reason: 'the socket opened');
    expect(statusCalls, 1, reason: 'the start-up status call is in flight');
    expect(settings.isAdmin.value, isFalse);

    firstStatus.complete(http.Response('unavailable', 503));
    await tester.pump();
    await tester.pump();

    expect(settings.sessionToken, token, reason: 'the session did not change');
    expect(channels, hasLength(1), reason: 'the socket did not reconnect');
    expect(statusCalls, 2, reason: 'the failed start-up call was retried');
    expect(settings.isAdmin.value, isTrue);
  });
}
