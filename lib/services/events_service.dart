import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/ws_connect_stub.dart'
    if (dart.library.io) 'package:quark/services/ws_connect_io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A single file-system mutation event from the server.
class FileEvent {
  final String kind;
  final String path;
  final String? newPath;

  /// The event's payload, as decoded JSON: the Job for a `job_*` event.
  final Object? data;

  const FileEvent({
    required this.kind,
    required this.path,
    this.newPath,
    this.data,
  });

  factory FileEvent.fromJson(Map<String, dynamic> json) => FileEvent(
    kind: json['kind'] as String? ?? '',
    path: json['path'] as String? ?? '',
    newPath: json['newPath'] as String?,
    data: json['data'],
  );
}

/// Maintains a WebSocket connection to `GET /api/v0/events` and broadcasts
/// incoming [FileEvent]s to listeners.
///
/// Usage:
/// ```dart
/// final sub = EventsService.instance.events.listen((evt) {
///   if (evt.kind == 'upload' || evt.kind == 'delete') {
///     refresh();
///   }
/// });
/// // on dispose:
/// sub.cancel();
/// ```
class EventsService {
  EventsService._();
  static final EventsService instance = EventsService._();

  final _controller = StreamController<FileEvent>.broadcast();

  Stream<FileEvent> get events => _controller.stream;

  final _connections = StreamController<void>.broadcast();

  /// Fires each time the socket opens, reconnects included.
  ///
  /// The Quark closes an account's socket without sending the event that
  /// caused it when that account is promoted, demoted, turned off or deleted,
  /// so anything that depends on the account refreshes here as well.
  Stream<void> get connections => _connections.stream;

  final _reconnects = StreamController<void>.broadcast();

  /// Fires each time the socket opens again after the first time since
  /// [start].
  ///
  /// Events published while the socket was down are gone, so a listing that
  /// follows events reloads here. The first connection is left out: a page
  /// already loads on its own when it opens.
  Stream<void> get reconnects => _reconnects.stream;
  bool _hasConnected = false;

  /// Opens the socket. A test swaps in a fake channel.
  @visibleForTesting
  static WebSocketChannel Function(Uri uri, {Map<String, dynamic>? headers})
  connectChannel = connectLocalTrustWs;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _listeningForToken = false;
  int _attempt = 0;

  static const _baseReconnectDelay = Duration(seconds: 2);
  static const _maxReconnectDelay = Duration(minutes: 1);

  /// Start the WebSocket connection. Safe to call multiple times — no-ops if
  /// already connected. Call [stop] first if you want to force a reconnect.
  void start() {
    _disposed = false;
    // The endpoint sits behind requireAuth, so a token appearing (login) or
    // changing (re-login as another user) has to drive a reconnect.
    if (!_listeningForToken) {
      AppSettings.instance.sessionTokenNotifier.addListener(_onTokenChanged);
      _listeningForToken = true;
    }
    if (_channel != null) return;
    _connect();
  }

  /// Stop the connection and cancel any pending reconnect.
  void stop() {
    _disposed = true;
    if (_listeningForToken) {
      AppSettings.instance.sessionTokenNotifier.removeListener(_onTokenChanged);
      _listeningForToken = false;
    }
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _attempt = 0;
    _hasConnected = false;
  }

  /// Drops any existing connection and reconnects with the current token.
  void _onTokenChanged() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _attempt = 0;
    if (AppSettings.instance.sessionToken != null) _connect();
  }

  void _connect() {
    if (_disposed) return;
    final host = AppSettings.instance.activeHost;
    if (host == null) {
      // No host configured — don't schedule reconnect; caller must call start()
      // again once a host is set (e.g. from AppSettings change listener).
      return;
    }

    final token = AppSettings.instance.sessionToken;
    if (token == null) {
      // Unauthenticated: the server would answer the upgrade with a 401. The
      // router lets us reach this page with no token when the quark is
      // unreachable, so wait for _onTokenChanged rather than hammering it.
      debugPrint('[EventsService] no session token — deferring connect');
      return;
    }

    try {
      final httpUri = Uri.parse(host).resolve('/api/v0/events');
      final wsUri = httpUri.replace(
        scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
        queryParameters: {'token': token},
      );
      // connectLocalTrustWs is resolved at compile time:
      //   - dart.library.io  → ws_connect_io.dart  (native: trusts local self-signed certs)
      //   - otherwise        → ws_connect_stub.dart (web: browser handles cert trust)
      // The token goes in both the query (the only option on web) and the
      // Authorization header (ignored on web); requireAuth accepts either.
      final channel = connectChannel(
        wsUri,
        headers: {'Authorization': 'Bearer $token'},
      );
      _channel = channel;

      // The connect failure (bad TLS, 401, refused) surfaces on `ready`. Without
      // awaiting it the rejection is an unhandled async error that crashes into
      // the Flutter error handler instead of our reconnect path.
      channel.ready
          .then((_) {
            if (!identical(channel, _channel)) return;
            _attempt = 0;
            debugPrint('[EventsService] connected to ${_redact(wsUri)}');
            _connections.add(null);
            if (_hasConnected) _reconnects.add(null);
            _hasConnected = true;
          })
          .catchError((Object e) {
            debugPrint('[EventsService] connect failed: $e');
            _onDisconnect(channel);
          });

      _sub = channel.stream.listen(
        (data) {
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            _controller.add(FileEvent.fromJson(json));
          } catch (_) {
            // Ignore malformed frames
          }
        },
        onError: (_) => _onDisconnect(channel),
        onDone: () => _onDisconnect(channel),
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[EventsService] connect error: $e');
      _onDisconnect(_channel);
    }
  }

  /// Tears down [channel] and schedules a retry, ignoring callbacks that arrive
  /// late from a channel we already replaced.
  void _onDisconnect(WebSocketChannel? channel) {
    if (channel != null && !identical(channel, _channel)) return;
    _sub?.cancel();
    _sub = null;
    _channel = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    // Back off exponentially — a quark that is down, or a token the server
    // rejects, shouldn't be retried twelve times a minute forever.
    final delayMs = _baseReconnectDelay.inMilliseconds * (1 << _attempt);
    final delay = Duration(
      milliseconds: delayMs.clamp(
        _baseReconnectDelay.inMilliseconds,
        _maxReconnectDelay.inMilliseconds,
      ),
    );
    if (delayMs < _maxReconnectDelay.inMilliseconds) _attempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _connect);
  }

  /// Strips the token from a URI so it never reaches the logs.
  static String _redact(Uri uri) => uri.queryParameters.containsKey('token')
      ? uri.replace(queryParameters: {'token': 'REDACTED'}).toString()
      : uri.toString();
}
