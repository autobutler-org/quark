import 'dart:async';

import 'package:quark/services/events_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The default [EventsService.connectChannel], captured before any test
/// replaces it.
final connectLocalTrustWsDefault = EventsService.connectChannel;

/// An event socket the test drives: it opens at once, or when [open] is
/// called for one made with `opened: false`, and closes when the test says
/// the Quark closed it.
///
/// One made with `opened: false` and never opened is a socket that never
/// says anything, so a page loads once and stays put.
class FakeChannel implements WebSocketChannel {
  FakeChannel({bool opened = true}) {
    if (opened) _ready.complete();
  }

  final _ready = Completer<void>();
  final _incoming = StreamController<dynamic>();

  @override
  Future<void> get ready => _ready.future;

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _FakeSink();

  /// Opens a socket made with `opened: false`.
  void open() => _ready.complete();

  void closeFromServer() => _incoming.close();

  void send(String frame) => _incoming.add(frame);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A sink that accepts a close and nothing else.
class _FakeSink implements WebSocketSink {
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
