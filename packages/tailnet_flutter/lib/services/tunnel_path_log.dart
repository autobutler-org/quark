/// Turns the bridge's peer status into debug log lines (#3883).
///
/// The bridge keeps the Quark's latest path changes and request timings. A
/// debug build reads them every so often; [TunnelPathLog] remembers what it
/// has already logged and returns only what is new, so each change and each
/// request is logged once.
library;

/// Remembers the newest path change and request already logged.
class TunnelPathLog {
  DateTime? _lastChange;
  DateTime? _lastRequest;

  /// Forgets what was logged, for a node that just started.
  void reset() {
    _lastChange = null;
    _lastRequest = null;
  }

  /// The lines for whatever in [peerStatus] is newer than the last call.
  ///
  /// [peerStatus] is the JSON `EmbeddedTunnel.peerStatus` returns. A path
  /// change reads `path: relay (nyc) at <time>`; a request reads
  /// `request files 200: headers 120.0 ms, body 340.5 ms, 12345 bytes`.
  List<String> lines(Map<String, dynamic> peerStatus) {
    final lines = <String>[];
    for (final change in _entries(peerStatus['pathChanges'])) {
      final at = DateTime.tryParse(change['at'] as String? ?? '');
      if (at == null || !_isNew(at, _lastChange)) continue;
      _lastChange = at;
      lines.add('path: ${change['path']} at ${at.toIso8601String()}');
    }
    for (final request in _entries(peerStatus['requests'])) {
      final at = DateTime.tryParse(request['at'] as String? ?? '');
      if (at == null || !_isNew(at, _lastRequest)) continue;
      _lastRequest = at;
      lines.add(
        'request ${request['route']} ${request['status']}: '
        'headers ${request['headersMs']} ms, body ${request['bodyMs']} ms, '
        '${request['bytes']} bytes',
      );
    }
    return lines;
  }

  static bool _isNew(DateTime at, DateTime? last) =>
      last == null || at.isAfter(last);

  static Iterable<Map<String, dynamic>> _entries(Object? list) =>
      list is List ? list.whereType<Map<String, dynamic>>() : const [];
}
