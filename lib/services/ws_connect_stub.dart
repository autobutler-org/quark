// Stub for non-io platforms (web). Returns a plain WebSocketChannel.
//
// Browsers don't allow custom headers on the WebSocket handshake, so [headers]
// is ignored — on web the session token travels in the `?token=` query
// parameter, which the server's requireAuth middleware also accepts.
import 'package:web_socket_channel/web_socket_channel.dart';

/// The web build's WebSocket connect, which has no certificate override to apply. The browser handles TLS trust,
/// so this is a plain connect.
WebSocketChannel connectLocalTrustWs(
  Uri uri, {
  Map<String, dynamic>? headers,
}) => WebSocketChannel.connect(uri);
