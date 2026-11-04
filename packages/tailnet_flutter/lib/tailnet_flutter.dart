/// The on-device tailnet node for iOS and Android (#1881).
///
/// [EmbeddedTunnel] joins the tailnet and serves a plain HTTP proxy on
/// 127.0.0.1. Web and desktop builds get the stub. The proxy token client
/// imports `dart:io`, so IO-only callers import
/// `package:tailnet_flutter/services/tunnel_token_client.dart` themselves.
/// Quark is the current app; the package stays in this repo until the API is
/// ready to move (#3637).
library;

export 'services/embedded_tunnel.dart';
