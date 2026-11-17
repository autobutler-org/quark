// cspell:words ffi

/// The on-device tailnet node for iOS and Android (#1881).
///
/// The phone joins the tailnet itself, so the user does not install the
/// official Tailscale app. [EmbeddedTunnel] is the whole API: [enroll] joins
/// the tailnet and starts a plain HTTP proxy on 127.0.0.1, [warm] restarts or
/// stops it, and [status] reports the node. [peerStatus] and [ping] say
/// whether traffic to the Quark goes direct or through a relay, for debugging
/// slow remote access (#3883). The proxy dials the Quark. The app's remote
/// address becomes that proxy, and [ConnectionController] already sends every
/// request there. The proxy forwards only requests that carry the token it
/// hands this app on each start; `tunnel_token_client.dart` adds it.
///
/// Web builds export the stub, which reports the tunnel unavailable. A browser
/// cannot run a node. Desktop reports the tunnel unavailable too, until a
/// desktop node ships (#2877).
library;

import 'package:flutter/foundation.dart';
import 'package:tailnet_flutter/services/embedded_tunnel_stub.dart'
    if (dart.library.ffi) 'package:tailnet_flutter/services/embedded_tunnel_io.dart'
    as impl;

/// The header the proxy sets on an answer it wrote itself because the Quark
/// never answered over the tunnel: the dial failed or timed out, or no
/// response headers came in time (#3884). Its value is `timeout` or
/// `unreachable`. The Quark never sets it, so a response carrying it means the
/// remote-access path is down, not that the Quark refused. HTTP header names
/// are case-insensitive; `package:http` hands them back lowercase.
/// `cmd/tsnetbridge/proxy.go` names the same one.
const tunnelUnavailableHeader = 'x-quark-tunnel-unavailable';

/// Called when the proxy answers a request with [tunnelUnavailableHeader]:
/// the Quark never answered over the tunnel (#3884). The app points it at its
/// connection check; `tunnel_token_client.dart` calls it. Null does nothing.
void Function()? onTunnelUnavailable;

/// Asks the Quark something cheap through the proxy at the URL it is given,
/// and says whether it answered. A return to the foreground keeps a `Running`
/// node this answers through and restarts any other (#3882). The app points
/// it at its own reachability probe. Null keeps any `Running` node.
Future<bool> Function(String proxyUrl)? tunnelHealthProbe;

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
/// checks it when the app comes back. There is no background transfer.
abstract final class EmbeddedTunnel {
  /// Whether this platform loads the native bridge.
  static bool get isSupported => impl.tunnelIsSupported;

  /// Whether remote access can run on the device this build is on.
  ///
  /// True on iOS and Android. False on web, where the page is already at
  /// whichever address the browser opened, and on desktop until that node
  /// ships (#2877, #3779).
  static bool get runsOnDeviceNode => !kIsWeb && isSupported;

  /// The node's current state.
  static Future<TunnelStatus> status() async =>
      TunnelStatus.fromJson(await impl.tunnelStatusJson());

  /// How traffic to the Quark travels, for debugging slow remote access
  /// (#3883).
  ///
  /// The bridge's JSON as it is: `state`; `quark`, the Quark's current path
  /// (`path` is `direct`, `relay`, `peer-relay`, `idle` or `unknown`, with
  /// `network` `lan` or `internet` when direct, `relayRegion` when relayed,
  /// `lastHandshake`, `rxBytes`, `txBytes`), or null without a node;
  /// `pathChanges`, the latest moves between direct and relayed with their
  /// times; and `requests`, the latest requests the proxy carried with their
  /// route, status, time to headers and to the end of the body, and size. It
  /// holds no keys, tokens or full addresses. Debug tooling only: never shown
  /// to a user as it is.
  static Future<Map<String, dynamic>> peerStatus() =>
      impl.tunnelPeerStatusJson();

  /// Pings the Quark [count] times inside the tunnel and over TCP through it
  /// (#3883), and returns the bridge's JSON: `tunnel` and `tcp`, each with
  /// `sent`, `received`, `minMs`, `avgMs`, and `error`; `tunnel` also has
  /// `path`, how the last answer traveled. `tunnel` is null without a node.
  /// Takes up to a few seconds per ping. Debug tooling only.
  static Future<Map<String, dynamic>> ping({int count = 5}) =>
      impl.tunnelPingJson(count);

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
  /// key and the state this call leaves on disk. A node already running is
  /// stopped first, and a node that does not start throws, so the caller
  /// never keeps a pairing it cannot connect with (#3776).
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

  /// Checks the node when the app comes back from the background (#3882).
  ///
  /// [onResume] is called as the check starts, with a future that completes
  /// once the node is known good or has been restarted, so the caller can
  /// hold its own work until then and run its address check after. A node
  /// that is `Running` and answers [tunnelHealthProbe] through its proxy
  /// keeps its port and token. Any other is restarted, and the port can
  /// change. An overlay or system prompt (Control Center, Face ID, the share
  /// sheet) is not a return and does nothing.
  static void watchLifecycle(
    void Function(Future<void> reconnected) onResume,
  ) => impl.tunnelWatch(onResume);
}
