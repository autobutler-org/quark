// cspell:words tsnetbridge

/// Sends the embedded tunnel proxy's token with every request the app makes
/// to that proxy (#1881).
///
/// The proxy on 127.0.0.1 forwards only a request that carries the token it
/// handed this app when it started, so another app on the phone cannot use it
/// to reach the Quark. Requests go to it from the `http` package, `dart:io`
/// clients, image loaders and the events WebSocket alike, so the token is
/// added below all of them: [LocalTrustHttpOverrides] wraps every
/// [HttpClient] it creates in a [TunnelTokenHttpClient].
///
/// Imported by `dart:io` code only.
library;

import 'dart:io';

/// The header the proxy reads. `cmd/tsnetbridge/proxy.go` names the same one.
const tunnelTokenHeader = 'X-Quark-Tunnel-Token';

/// The running proxy's port and token, or null while it is stopped.
///
/// Set by the embedded tunnel when its proxy starts and cleared when it stops.
({int port, String token})? tunnelProxyCredentials;

/// An [HttpClient] that adds [tunnelTokenHeader] to each request bound for
/// the proxy, `http://127.0.0.1:<port>`, and to no other host.
class TunnelTokenHttpClient implements HttpClient {
  /// Wraps [inner]. [credentials] is read on every request, because the proxy
  /// restarts on a new port with a new token.
  TunnelTokenHttpClient(
    this._inner, {
    ({int port, String token})? Function()? credentials,
  }) : _credentials = credentials ?? (() => tunnelProxyCredentials);

  final HttpClient _inner;
  final ({int port, String token})? Function() _credentials;

  Future<HttpClientRequest> _tag(Future<HttpClientRequest> pending) async {
    final request = await pending;
    final current = _credentials();
    final uri = request.uri;
    if (current != null &&
        uri.host == '127.0.0.1' &&
        uri.port == current.port) {
      request.headers.set(tunnelTokenHeader, current.token);
    }
    return request;
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => _tag(_inner.open(method, host, port, path));

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _tag(_inner.openUrl(method, url));

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _tag(_inner.get(host, port, path));

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _tag(_inner.getUrl(url));

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _tag(_inner.post(host, port, path));

  @override
  Future<HttpClientRequest> postUrl(Uri url) => _tag(_inner.postUrl(url));

  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      _tag(_inner.put(host, port, path));

  @override
  Future<HttpClientRequest> putUrl(Uri url) => _tag(_inner.putUrl(url));

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _tag(_inner.delete(host, port, path));

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _tag(_inner.deleteUrl(url));

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _tag(_inner.patch(host, port, path));

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => _tag(_inner.patchUrl(url));

  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _tag(_inner.head(host, port, path));

  @override
  Future<HttpClientRequest> headUrl(Uri url) => _tag(_inner.headUrl(url));

  @override
  Duration get idleTimeout => _inner.idleTimeout;

  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;

  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;

  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;

  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;

  @override
  set maxConnectionsPerHost(int? value) => _inner.maxConnectionsPerHost = value;

  @override
  bool get autoUncompress => _inner.autoUncompress;

  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;

  @override
  String? get userAgent => _inner.userAgent;

  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) => _inner.authenticate = f;

  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addCredentials(url, realm, credentials);

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )?
    f,
  ) => _inner.connectionFactory = f;

  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;

  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
    f,
  ) => _inner.authenticateProxy = f;

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addProxyCredentials(host, port, realm, credentials);

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) => _inner.badCertificateCallback = callback;

  @override
  set keyLog(Function(String line)? callback) => _inner.keyLog = callback;

  @override
  void close({bool force = false}) => _inner.close(force: force);
}
