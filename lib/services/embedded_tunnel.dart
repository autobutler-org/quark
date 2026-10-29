// cspell:words ffi

/// The on-device tailnet node for iOS and Android (#1881).
///
/// The phone joins the tailnet itself, so the user does not install the
/// official Tailscale app. [EmbeddedTunnel] is the whole API: [enroll] joins
/// the tailnet and starts a plain HTTP proxy on 127.0.0.1, [warm] restarts or
/// stops it, and [status] reports the node. The proxy dials the Quark. The app's remote
/// address becomes that proxy, and [ConnectionController] already sends every
/// request there. The proxy forwards only requests that carry the token it
/// hands this app on each start; `tunnel_token_client.dart` adds it.
///
/// Web builds export the stub, which reports the tunnel unavailable. A browser
/// cannot run a node.
library;

import 'package:quark/services/embedded_tunnel_stub.dart'
    if (dart.library.ffi) 'package:quark/services/embedded_tunnel_io.dart'
    as impl;

/// What the bridge reports about its node.
///
/// Parsed from the JSON `quark_tsnet_status` returns:
/// `{state, tailnetIPs, port, error}`.
class TunnelStatus {
  /// Creates a status value.
  const TunnelStatus({
    required this.state,
    this.tailnetIPs = const [],
    this.port = 0,
    this.error = '',
  });

  /// Parses the bridge's status JSON.
  factory TunnelStatus.fromJson(Map<String, dynamic> json) => TunnelStatus(
    state: json['state'] as String? ?? 'Stopped',
    tailnetIPs: [
      for (final ip in json['tailnetIPs'] as List? ?? const []) ip as String,
    ],
    port: json['port'] as int? ?? 0,
    error: json['error'] as String? ?? '',
  );

  /// `Stopped`, `Starting`, or the backend state (`Running`, `NeedsLogin`).
  final String state;

  /// This device's own tailnet addresses.
  final List<String> tailnetIPs;

  /// The proxy port, 0 when it is not listening.
  final int port;

  /// The last start failure, empty when there was none.
  ///
  /// Diagnostic text for a log, not copy for a user.
  final String error;
}

/// The app's embedded tailnet node and its local proxy.
///
/// One per process. On iOS the node runs in the foreground only: [watchLifecycle]
/// restarts it when the app comes back. There is no background transfer.
abstract final class EmbeddedTunnel {
  /// Whether this platform loads the native bridge.
  static bool get isSupported => impl.tunnelIsSupported;

  /// The node's current state.
  static Future<TunnelStatus> status() async =>
      TunnelStatus.fromJson(await impl.tunnelStatusJson());

  /// The proxy URL in front of [upstream], or null when this platform has no
  /// node or the phone has not paired yet.
  ///
  /// [ConnectionController] probes this instead of the Quark's tailnet address.
  static Future<String?> proxyUrl(String upstream) =>
      impl.tunnelProxyUrl(upstream);

  /// Starts the proxy for a node that already has state on disk.
  ///
  /// Called while the phone can still reach the Quark at home. An empty
  /// [upstream] stops a running node: remote access is off, or this phone
  /// has paused it. The first enrollment is [enroll]. This does not ask the
  /// Quark for a key.
  static Future<void> warm(String upstream) => impl.tunnelWarm(upstream);

  /// Joins the tailnet with a freshly issued key and starts the proxy.
  ///
  /// [authKey] is single-use. Later starts go through [warm] with an empty
  /// key and the state this call leaves on disk.
  static Future<void> enroll({
    required String controlUrl,
    required String authKey,
    required String upstream,
  }) => impl.tunnelEnroll(
    controlUrl: controlUrl,
    authKey: authKey,
    upstream: upstream,
  );

  /// Stops the node and deletes its state, so nothing on this phone can
  /// rejoin the tailnet until a fresh key is enrolled (#3785).
  ///
  /// Signing out calls this, so the next person to sign in on the phone does
  /// not inherit the last one's node.
  static Future<void> forget() => impl.tunnelForget();

  /// Restarts the node when the app returns to the foreground, then calls
  /// [onReconnected] so the address check runs again. The port can change.
  static void watchLifecycle(void Function() onReconnected) =>
      impl.tunnelWatch(onReconnected);
}
