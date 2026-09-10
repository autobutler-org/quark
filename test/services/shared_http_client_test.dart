import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';

/// Records that it was closed, so a host switch can be shown to hand the old
/// connection pool back rather than leaking it.
class _FakeClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(const Stream.empty(), 200);

  @override
  void close() => closed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final settings = AppSettings.instance;

  Future<void> clearHosts() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  }

  setUp(clearHosts);
  tearDown(clearHosts);
  tearDown(resetSharedHttpClient);
  tearDown(() => sharedHttpClientFactory = buildLocalTrustHttpClient);

  /// The whole point of #1782: a second request must not pay another TCP
  /// connect plus TLS handshake.
  test('hands the same client back for the same host', () async {
    sharedHttpClientFactory = _FakeClient.new;
    await settings.addHost(
      HostEntry(name: 'One', hostAddress: 'http://one.local'),
    );

    final first = sharedHttpClient;
    expect(identical(sharedHttpClient, first), isTrue);
    expect(identical(sharedHttpClient, first), isTrue);
  });

  test(
    'rebuilds and closes the old client when the active host changes',
    () async {
      sharedHttpClientFactory = _FakeClient.new;
      await settings.addHost(
        HostEntry(name: 'One', hostAddress: 'http://one.local'),
      );
      await settings.addHost(
        HostEntry(name: 'Two', hostAddress: 'http://two.local'),
      );

      // addHost makes the new host active, so this is the client for two.local.
      final forTwo = sharedHttpClient as _FakeClient;

      await settings.setActiveIndex(0);
      final forOne = sharedHttpClient;

      expect(identical(forOne, forTwo), isFalse);
      expect(
        forTwo.closed,
        isTrue,
        reason: 'the old pool is worthless and must not be leaked',
      );
    },
  );

  test('reset closes the client and forces a rebuild', () async {
    sharedHttpClientFactory = _FakeClient.new;
    await settings.addHost(
      HostEntry(name: 'One', hostAddress: 'http://one.local'),
    );

    final first = sharedHttpClient as _FakeClient;
    resetSharedHttpClient();

    expect(first.closed, isTrue);
    expect(identical(sharedHttpClient, first), isFalse);
  });

  /// The default is still the local-trust builder, so self-signed LAN certs
  /// keep working and the connect timeout is still applied. `IOClient` keeps
  /// its inner `HttpClient` private, so the type is as far as a test can
  /// reach — `buildLocalTrustHttpClient` is what sets `connectionTimeout` and
  /// `badCertificateCallback` on it, and that function is unchanged.
  test('defaults to the local-trust client', () async {
    await settings.addHost(
      HostEntry(name: 'One', hostAddress: 'https://one.local'),
    );

    expect(sharedHttpClient, isA<IOClient>());
  });
}
