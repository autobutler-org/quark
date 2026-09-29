import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/chat_channel_keys_controller.dart';
import 'package:quark/controllers/chat_keys_controller.dart';
import 'package:quark/models/chat_channel_keys.dart';
import 'package:quark/models/chat_message.dart';
import 'package:quark/services/chat_channel_keys_service.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/services/chat_messages_service.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/error_text.dart';

/// One open channel's timeline (#2418): its messages, decrypted in memory,
/// merged with its membership and key events.
///
/// - [open] loads the newest page and the channel's events, and follows the
///   events socket: `chat_message_created` and `chat_message_deleted` for
///   messages, `chat_channel_changed` for events (a new one, or one its actor
///   just signed).
/// - The socket drops events when a client falls behind and has no replay, so
///   [catchUp] fetches `?after=` the newest id held, on [open] and on every
///   reconnect.
/// - [send] encrypts under the channel's current key version, binding the
///   channel id and version as additional data, and posts. [delete]
///   tombstones.
/// - A message under a key version this account has no grant of yet is
///   [ChatMessageState.waiting], and opens by itself once the grant lands
///   (the keys controller notifies).
/// - [entries] is the merged timeline, oldest first.
///
/// Plaintext is never written anywhere; [dispose] drops it. The chat page
/// makes one per open channel and disposes it on leaving.
class ChatMessagesController extends ChangeNotifier {
  /// Builds a controller for [channelId]. Every collaborator has a real
  /// default; tests pass fakes.
  ChatMessagesController({
    required this.channelId,
    ChatChannelKeysController? keys,
    ChatCrypto? Function()? crypto,
    Future<List<ChatMessage>> Function(
      int channelId, {
      int? before,
      int? after,
      int? limit,
    })?
    fetchMessages,
    Future<ChatMessage> Function(
      int channelId,
      int keyVersion,
      Uint8List ciphertext,
    )?
    postMessage,
    Future<ChatMessage> Function(int messageId)? deleteMessage,
    Future<List<ChatChannelEvent>> Function(int channelId, {int after})?
    fetchEvents,
    Stream<FileEvent>? events,
    Stream<void>? reconnects,
  }) : _keys = keys ?? ChatChannelKeysController.instance,
       _crypto = crypto ?? (() => ChatKeysController.instance.crypto),
       _fetchMessages = fetchMessages ?? ChatMessagesService.fetchMessages,
       _postMessage = postMessage ?? ChatMessagesService.postMessage,
       _deleteMessage = deleteMessage ?? ChatMessagesService.deleteMessage,
       _fetchEvents = fetchEvents ?? ChatChannelKeysService.fetchEvents,
       _eventStream = events ?? EventsService.instance.events,
       _reconnectStream = reconnects ?? EventsService.instance.reconnects;

  /// The channel this timeline is for.
  final int channelId;

  /// Messages per page of history.
  static const pageSize = 50;

  /// Events per page, the Quark's cap.
  static const _eventsPage = 200;

  final ChatChannelKeysController _keys;
  final ChatCrypto? Function() _crypto;
  final Future<List<ChatMessage>> Function(
    int channelId, {
    int? before,
    int? after,
    int? limit,
  })
  _fetchMessages;
  final Future<ChatMessage> Function(
    int channelId,
    int keyVersion,
    Uint8List ciphertext,
  )
  _postMessage;
  final Future<ChatMessage> Function(int messageId) _deleteMessage;
  final Future<List<ChatChannelEvent>> Function(int channelId, {int after})
  _fetchEvents;
  final Stream<FileEvent> _eventStream;
  final Stream<void> _reconnectStream;

  final SplayTreeMap<int, ChatTimelineMessage> _messages = SplayTreeMap();
  List<ChatTimelineSystem> _system = const [];
  final List<StreamSubscription<Object?>> _subs = [];
  Future<void>? _catchingUp;
  bool _disposed = false;

  /// Whether older messages may exist before the oldest one loaded.
  bool hasOlder = true;

  /// True while [open] runs, before anything is shown.
  bool isLoading = false;

  /// What went wrong in the last [open], [catchUp] or [loadOlder], for
  /// `Errors.message`; null when it worked.
  Object? error;

  /// Whether this account has no grant of the channel's current key yet, so
  /// it can't send.
  bool get isWaitingForKey =>
      _keys.keyFor(channelId, _keys.currentVersion(channelId)) == null;

  /// The timeline, oldest first: messages and system events merged by time,
  /// a system event first when both share a second. Events older than the
  /// loaded history are left out until [loadOlder] reaches them.
  List<ChatTimelineEntry> get entries {
    final oldest = hasOlder && _messages.isNotEmpty
        ? _messages[_messages.firstKey()]!.createdAt
        : null;
    final merged = <ChatTimelineEntry>[
      for (final s in _system)
        if (oldest == null || !s.createdAt.isBefore(oldest)) s,
      ..._messages.values,
    ];
    // ponytail: re-sorted per read; cache it if a long channel stutters.
    merged.sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      if (byTime != 0) return byTime;
      if (a is ChatTimelineSystem && b is ChatTimelineMessage) return -1;
      if (a is ChatTimelineMessage && b is ChatTimelineSystem) return 1;
      return _idOf(a).compareTo(_idOf(b));
    });
    return merged;
  }

  /// Loads the newest page and the channel's events, and starts following the
  /// socket. Failures land in [error].
  Future<void> open() async {
    if (_subs.isEmpty) {
      _subs
        ..add(_eventStream.listen(_onEvent))
        ..add(_reconnectStream.listen((_) => catchUp()));
      _keys.addListener(_onKeysChanged);
    }
    isLoading = true;
    _notify();
    try {
      await _keys.ensureKeys(channelId);
      final page = await _fetchMessages(channelId, limit: pageSize);
      hasOlder = page.length == pageSize;
      page.forEach(_put);
      await catchUp();
      error = null;
    } catch (e) {
      error = e;
    } finally {
      isLoading = false;
      _notify();
    }
  }

  /// Fetches every message after the newest one held, and the channel's
  /// events. Concurrent calls share one run.
  Future<void> catchUp() => _catchingUp ??= _catchUp().whenComplete(() {
    _catchingUp = null;
  });

  /// Loads the page before the oldest message held.
  Future<void> loadOlder() async {
    if (!hasOlder || _messages.isEmpty) return;
    try {
      final page = await _fetchMessages(
        channelId,
        before: _messages.firstKey(),
        limit: pageSize,
      );
      hasOlder = page.length == pageSize;
      page.forEach(_put);
      error = null;
    } catch (e) {
      error = e;
    }
    _notify();
  }

  /// Encrypts [text] under the channel's current key and posts it. Throws a
  /// [MessageException] while waiting for the key or when the message is over
  /// the Quark's cap; network failures propagate as the service throws them.
  Future<void> send(String text) async {
    final crypto = _crypto();
    if (crypto == null) throw StateError('chat is locked');
    var version = _keys.currentVersion(channelId);
    var key = _keys.keyFor(channelId, version);
    if (key == null) {
      await _keys.ensureKeys(channelId);
      version = _keys.currentVersion(channelId);
      key = _keys.keyFor(channelId, version);
    }
    if (key == null) throw const MessageException(Errors.chatWaitingForKey);
    final ciphertext = crypto.encrypt(
      Uint8List.fromList(utf8.encode(text)),
      key,
      additionalData: crypto.messageAad(
        channelId: channelId,
        keyVersion: version,
      ),
    );
    if (ciphertext.length > ChatMessagesService.maxCiphertextBytes) {
      throw const MessageException(Errors.chatMessageTooLong);
    }
    final stored = await _postMessage(channelId, version, ciphertext);
    _put(stored, text: text);
    _notify();
  }

  /// Deletes message [messageId]: this account's own, or anyone's in a
  /// channel it owns.
  Future<void> delete(int messageId) async {
    _put(await _deleteMessage(messageId));
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final sub in _subs) {
      sub.cancel();
    }
    _keys.removeListener(_onKeysChanged);
    _messages.clear();
    _system = const [];
    super.dispose();
  }

  Future<void> _catchUp() async {
    try {
      while (true) {
        final after = _messages.isEmpty ? 0 : _messages.lastKey()!;
        final page = await _fetchMessages(
          channelId,
          after: after,
          limit: ChatMessagesService.maxPage,
        );
        if (_disposed) return;
        page.forEach(_put);
        if (page.length < ChatMessagesService.maxPage) break;
      }
      await _reloadEvents();
      error = null;
    } catch (e) {
      error = e;
    }
    _notify();
  }

  /// Fetches every event again, since a signature can land on an old one.
  // ponytail: whole list each time; page after the newest verified event if
  // a channel's history of joins and rotations grows long.
  Future<void> _reloadEvents() async {
    final events = <ChatChannelEvent>[];
    while (true) {
      final page = await _fetchEvents(
        channelId,
        after: events.isEmpty ? 0 : events.last.id,
      );
      events.addAll(page);
      if (page.length < _eventsPage) break;
    }
    if (_disposed) return;
    _system = [
      for (final e in events)
        ChatTimelineSystem(event: e, isVerified: _keys.verifyEvent(e)),
    ];
  }

  /// Stores [message], decrypting it unless [text] is already known.
  void _put(ChatMessage message, {String? text}) {
    if (message.channelId != channelId) return;
    _messages[message.id] = text != null && !message.isDeleted
        ? ChatTimelineMessage(
            message: message,
            state: ChatMessageState.ready,
            text: text,
          )
        : _open(message);
  }

  ChatTimelineMessage _open(ChatMessage message) {
    ChatTimelineMessage as(ChatMessageState state, [String? text]) =>
        ChatTimelineMessage(message: message, state: state, text: text);
    final ciphertext = message.ciphertext;
    if (message.isDeleted || ciphertext == null) {
      return as(ChatMessageState.deleted);
    }
    final key = _keys.keyFor(channelId, message.keyVersion);
    final crypto = _crypto();
    if (key == null || crypto == null) return as(ChatMessageState.waiting);
    try {
      final plain = crypto.decrypt(
        ciphertext,
        key,
        additionalData: crypto.messageAad(
          channelId: channelId,
          keyVersion: message.keyVersion,
        ),
      );
      return as(ChatMessageState.ready, utf8.decode(plain));
    } on Object catch (e) {
      debugPrint(
        '[chat_messages_controller.dart] message ${message.id} in channel '
        '$channelId won\'t open: $e',
      );
      return as(ChatMessageState.unreadable);
    }
  }

  /// Opens waiting messages whose key just landed, and drops the text of
  /// any whose key is gone, as when chat locks and the keys are forgotten.
  void _onKeysChanged() {
    var changed = false;
    for (final entry in _messages.values.toList()) {
      final keyless =
          _crypto() == null ||
          _keys.keyFor(channelId, entry.message.keyVersion) == null;
      final stale = switch (entry.state) {
        ChatMessageState.waiting => !keyless,
        ChatMessageState.ready => keyless,
        _ => false,
      };
      if (!stale) continue;
      _messages[entry.message.id] = _open(entry.message);
      changed = true;
    }
    if (changed) _notify();
  }

  void _onEvent(FileEvent event) {
    final data = event.data;
    if (data is! Map || (data['channelId'] as num?)?.toInt() != channelId) {
      return;
    }
    switch (event.kind) {
      case 'chat_message_created':
        final message = data['message'];
        if (message is! Map<String, dynamic>) return;
        _put(ChatMessage.fromJson(message));
        _notify();
      case 'chat_message_deleted':
        final id = (data['messageId'] as num?)?.toInt();
        final held = _messages[id];
        if (held == null) return;
        _put(held.message.tombstone(DateTime.now().toUtc()));
        _notify();
      case 'chat_channel_changed':
        _reloadEvents().then((_) => _notify()).catchError((Object e) {
          debugPrint('[chat_messages_controller.dart] channel $channelId: $e');
        });
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static int _idOf(ChatTimelineEntry entry) => switch (entry) {
    ChatTimelineMessage(:final message) => message.id,
    ChatTimelineSystem(:final event) => event.id,
  };
}
