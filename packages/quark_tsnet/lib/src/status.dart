/// What the Go bridge reports about its tailnet node.
///
/// Parsed from the JSON `quark_tsnet_status` returns:
/// `{state, tailnetIPs, port, error}`.
class TsnetStatus {
  /// Creates a status value.
  const TsnetStatus({
    required this.state,
    this.tailnetIPs = const [],
    this.port = 0,
    this.error = '',
  });

  /// Parses the bridge's status JSON.
  factory TsnetStatus.fromJson(Map<String, dynamic> json) => TsnetStatus(
    state: json['state'] as String? ?? 'Stopped',
    tailnetIPs: [
      for (final ip in json['tailnetIPs'] as List? ?? const []) ip as String,
    ],
    port: json['port'] as int? ?? 0,
    error: json['error'] as String? ?? '',
  );

  /// `Stopped`, `Starting`, or tailscale's backend state (`Running`,
  /// `NeedsLogin`, ...).
  final String state;

  /// This device's own tailnet addresses.
  final List<String> tailnetIPs;

  /// The loopback proxy port, 0 when stopped.
  final int port;

  /// The last start failure, empty when there was none. Diagnostic text for
  /// logs, not copy for a user.
  final String error;

  /// Whether the node is up and the proxy is serving.
  bool get isRunning => state == 'Running' && port > 0;

  /// The base URL to point the app's HTTP clients at, or null when stopped.
  Uri? get loopbackUrl =>
      isRunning ? Uri.parse('http://127.0.0.1:$port') : null;
}

/// Thrown when the bridge fails to start. [message] is the bridge's own
/// diagnostic text, not copy for a user.
class TsnetException implements Exception {
  /// Creates the exception.
  const TsnetException(this.message);

  /// The bridge's error text.
  final String message;

  @override
  String toString() => 'TsnetException: $message';
}
