// IO implementation: trusts self-signed certs from local hosts.
import 'dart:io';

import 'package:quark/services/local_trust.dart';
import 'package:quark/services/local_trust_pin_io.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Connects to [uri] over WebSocket, trusting self-signed certificates when the
/// configured host is a local/LAN address (see [isLocalTrustHost]).
///
/// [headers] are sent with the upgrade request — used to pass the session token
/// as a `Authorization: Bearer` header, which the web build cannot do.
///
/// Decision is made on [uri.host] **before** the TLS handshake — the same
/// approach used by [buildLocalTrustHttpClient] for HTTP. This avoids the iOS
/// bug where [HttpClient.badCertificateCallback] receives a hostname that
/// doesn't match the IP stored in AppSettings (e.g. mDNS resolution or SNI
/// mismatch), causing the callback to return false and the handshake to fail.
///
/// api: none
WebSocketChannel connectLocalTrustWs(Uri uri, {Map<String, dynamic>? headers}) {
  if (!isLocalTrustHost(uri.host)) {
    // Non-local host: use standard TLS verification.
    return IOWebSocketChannel.connect(uri, headers: headers);
  }

  // Local host: trust its self-signed cert, but never a public name the TLS
  // layer reports, and only the certificate the saved Quark is pinned to
  // (#2721), consistent with buildLocalTrustHttpClient() in
  // authenticated_service.dart.
  final httpClient = HttpClient()
    ..badCertificateCallback = (cert, host, port) =>
        isLocalTrustHost(host) && acceptsPinnedCertificate(cert, '$uri');
  return IOWebSocketChannel.connect(
    uri,
    headers: headers,
    customClient: httpClient,
  );
}
