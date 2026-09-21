// IO implementation of the loopback media proxy. See local_media_proxy.dart
// for what this is for and why it exists.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/local_media_proxy.dart';
import 'package:quark/services/local_trust.dart';

/// Borrows the app's standard `Authorization: Bearer` header so proxied media
/// requests authenticate the same way every other API call does.
class _MediaAuth with AuthenticatedService {}

/// Request headers worth passing upstream.
///
/// `range` and `if-range` are the ones that matter: AVPlayer and ExoPlayer
/// both seek by issuing byte-range requests, and the quark's download
/// endpoint answers them through Go's `http.ServeContent`. Dropping them here
/// would turn every seek into a full re-download.
const _forwardedRequestHeaders = <String>['range', 'if-range', 'accept'];

/// Response headers the player needs to see to seek and to pick a decoder.
const _forwardedResponseHeaders = <String>[
  'content-type',
  'content-range',
  'accept-ranges',
  'last-modified',
  'etag',
];

/// Starts a loopback proxy for [upstream] on a random port, forwarding range requests so the native player can
/// seek. Uses the app's auth header unless [headers] is given.
Future<LocalMediaProxy> startLocalMediaProxy(
  Uri upstream, {
  Map<String, String>? headers,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  // Re-compressing an already-compressed media container only muddies
  // content-length and content-range.
  server.autoCompress = false;
  final proxy = _LocalMediaProxyIo(
    server: server,
    upstream: upstream,
    headers: Map.unmodifiable(headers ?? _MediaAuth().authHeaders),
  );
  proxy._listen();
  return proxy;
}

class _LocalMediaProxyIo implements LocalMediaProxy {
  _LocalMediaProxyIo({
    required HttpServer server,
    required Uri upstream,
    required Map<String, String> headers,
  }) : _server = server,
       _upstream = upstream,
       _headers = headers,
       _token = _generateToken() {
    _client = HttpClient()
      ..badCertificateCallback = _shouldTrustCertificate
      // Keeping the bytes uncompressed keeps content-length and content-range
      // honest end to end. Media containers are already compressed.
      ..autoUncompress = false;
  }

  final HttpServer _server;
  final Uri _upstream;
  final Map<String, String> _headers;
  final String _token;
  late final HttpClient _client;

  MediaUpstreamException? _lastUpstreamError;
  bool _closed = false;

  static final _random = Random.secure();

  static String _generateToken() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Trusts a self-signed certificate only when the pinned upstream host is
  /// local.
  ///
  /// The decision comes from [isLocalTrustHost] rather than a copy of its
  /// rules, and it is made against the URL this proxy was constructed with —
  /// not against whatever hostname the TLS layer reports. iOS has been seen
  /// handing back an mDNS-resolved address that doesn't match the configured
  /// host, which is the same trap `connectLocalTrustWs` sidesteps.
  bool _shouldTrustCertificate(X509Certificate cert, String host, int port) {
    return isLocalTrustHost(_upstream.host) || isLocalTrustHost(host);
  }

  @override
  Uri get localUrl => Uri(
    scheme: 'http',
    host: _server.address.address,
    port: _server.port,
    path: '/$_token',
  );

  @override
  Uri get upstreamUrl => _upstream;

  @override
  MediaUpstreamException? get lastUpstreamError => _lastUpstreamError;

  void _listen() {
    _server.listen(
      (request) {
        // Each request is independent; a failure on one must not tear down the
        // listener, because the player will simply open another socket.
        unawaited(_handle(request));
      },
      onError: (Object error) {
        debugPrint('[local_media_proxy] server error: $error');
      },
      cancelOnError: false,
    );
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;

    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await _finish(response);
      return;
    }

    // One pinned upstream, one unguessable path. Anything else gets a 404, so
    // this is never usable as a general forward proxy by another process on
    // the device.
    if (request.uri.path != '/$_token') {
      response.statusCode = HttpStatus.notFound;
      await _finish(response);
      return;
    }

    try {
      await _forward(request, response);
    } on Object catch (error) {
      debugPrint('[local_media_proxy] forward failed: $error');
      _lastUpstreamError ??= MediaUpstreamException(
        HttpStatus.badGateway,
        'could not reach ${_upstream.host}',
      );
      try {
        response.statusCode = HttpStatus.badGateway;
      } on Object catch (_) {
        // Headers already went out; nothing left to say.
      }
      await _finish(response);
    }
  }

  Future<void> _forward(HttpRequest request, HttpResponse response) async {
    final upstreamRequest = await _client.openUrl(request.method, _upstream);
    upstreamRequest.followRedirects = true;

    for (final name in _forwardedRequestHeaders) {
      final values = request.headers[name];
      if (values == null) continue;
      for (final value in values) {
        upstreamRequest.headers.add(name, value);
      }
    }
    _headers.forEach(upstreamRequest.headers.set);
    upstreamRequest.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');

    final upstreamResponse = await upstreamRequest.close();
    final status = upstreamResponse.statusCode;

    // 416 is a legitimate answer to a seek past the end, not a broken file, so
    // it is passed through without being remembered as the reason playback
    // failed.
    if (status >= 400 && status != HttpStatus.requestedRangeNotSatisfiable) {
      _lastUpstreamError ??= MediaUpstreamException(
        status,
        upstreamResponse.reasonPhrase,
      );
    }

    response.statusCode = status;
    for (final name in _forwardedResponseHeaders) {
      final values = upstreamResponse.headers[name];
      if (values == null) continue;
      response.headers.removeAll(name);
      for (final value in values) {
        response.headers.add(name, value);
      }
    }

    final contentLength = upstreamResponse.contentLength;
    if (contentLength >= 0) {
      response.contentLength = contentLength;
    }

    if (request.method == 'HEAD') {
      await upstreamResponse.drain<void>();
      await _finish(response);
      return;
    }

    // The whole point of the exercise: bytes move through, they are never
    // collected. Memory stays flat whether the file is 3 MB or 30 GB.
    try {
      await response.addStream(upstreamResponse);
    } on Object catch (error) {
      // The player closes sockets abruptly when it seeks or stops. That is
      // normal, not a playback failure.
      debugPrint('[local_media_proxy] stream ended early: $error');
    }
    await _finish(response);
  }

  Future<void> _finish(HttpResponse response) async {
    try {
      await response.close();
    } on Object catch (_) {
      // Already closed by the peer.
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close(force: true);
    await _server.close(force: true);
  }
}
