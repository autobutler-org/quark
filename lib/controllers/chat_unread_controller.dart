import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/chat_channels_service.dart';
import 'package:quark/services/events_service.dart';

/// How many chat messages the signed-in account has not read, per channel,
/// and its read markers (#2424). One [instance] serves the chat page's
/// channel list and the drawer's dot, so they never disagree.
///
/// - The counts are the Quark's: [refresh] reads them off the channel list,
///   and the chat page hands over the list it already loaded with
///   [setChannels].
/// - [markRead] moves a channel's marker forward and takes the count the
///   Quark answers with. Each marker is sent once, and never one at or
///   behind the newest this client has sent or heard of.
/// - `chat_read_marker_changed`, which only this account's sessions hear,
///   carries the marker and count another session set, so reading a channel
///   on one device clears it on the others.
/// - `chat_message_created` from someone else adds one to its channel. A
///   deleted message may or may not have been counted, so
///   `chat_message_deleted` reads the counts again, as do
///   `chat_channel_changed` and `resync`.
///
/// Nothing is followed until the first [refresh], [setChannels] or
/// [markRead]. A failure keeps the counts it had: a count is a hint, and the
/// next refresh corrects it.
class ChatUnreadController extends ChangeNotifier {
  /// Builds a controller. Every collaborator has a real default; tests pass
  /// fakes.
  ChatUnreadController({
    Future<List<ChatChannel>> Function() listChannels =
        ChatChannelsService.listChannels,
    Future<ChatReadMarker> Function(int channelId, int messageId) markRead =
        ChatChannelsService.markRead,
    int? Function()? currentUserId,
    Stream<FileEvent>? events,
  }) : _listChannels = listChannels,
       _markRead = markRead,
       _currentUserId =
           currentUserId ?? (() => AppSettings.instance.userId.value),
       _eventStream = events;

  /// The one the app uses.
  static final ChatUnreadController instance = ChatUnreadController();

  final Future<List<ChatChannel>> Function() _listChannels;
  final Future<ChatReadMarker> Function(int channelId, int messageId) _markRead;
  final int? Function() _currentUserId;
  final Stream<FileEvent>? _eventStream;
  StreamSubscription<FileEvent>? _events;

  Map<int, int> _counts = const {};

  /// The newest message id sent or heard as each channel's marker.
  final Map<int, int> _markers = {};

  /// How many unread messages channel [channelId] holds; zero for one never
  /// heard of.
  int countOf(int channelId) => _counts[channelId] ?? 0;

  /// Whether any channel holds an unread message.
  bool get hasUnread => _counts.values.any((count) => count > 0);

  /// Reads every channel's count from the Quark.
  Future<void> refresh() async {
    _follow();
    try {
      setChannels(await _listChannels());
    } catch (e) {
      debugPrint('chat: unread counts not loaded: $e');
    }
  }

  /// Takes the counts from [channels], a list just loaded.
  void setChannels(List<ChatChannel> channels) {
    _follow();
    _counts = {for (final c in channels) c.id: c.unreadCount};
    notifyListeners();
  }

  /// Moves channel [channelId]'s read marker to message [messageId], unless
  /// the marker is already there or past it. A failure is forgotten, so the
  /// next call tries again.
  Future<void> markRead(int channelId, int messageId) async {
    _follow();
    final standing = _markers[channelId];
    if (standing != null && messageId <= standing) return;
    _markers[channelId] = messageId;
    try {
      _apply(await _markRead(channelId, messageId));
    } catch (e) {
      debugPrint('chat: read marker not set for channel $channelId: $e');
      if (_markers[channelId] != messageId) return;
      if (standing == null) {
        _markers.remove(channelId);
      } else {
        _markers[channelId] = standing;
      }
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  void _follow() => _events ??= (_eventStream ?? EventsService.instance.events)
      .listen(_onEvent);

  void _apply(ChatReadMarker marker) {
    _markers[marker.channelId] = max(
      _markers[marker.channelId] ?? 0,
      marker.lastReadMessageId,
    );
    _counts = {..._counts, marker.channelId: marker.unreadCount};
    notifyListeners();
  }

  void _onEvent(FileEvent event) {
    final data = event.data;
    switch (event.kind) {
      case 'chat_read_marker_changed':
        if (data is Map<String, dynamic> && data['channelId'] is num) {
          _apply(ChatReadMarker.fromJson(data));
        }
      case 'chat_message_created':
        if (data is! Map) return;
        final channelId = (data['channelId'] as num?)?.toInt();
        final message = data['message'];
        final authorId = message is Map
            ? (message['authorId'] as num?)?.toInt()
            : null;
        if (channelId == null || authorId == _currentUserId()) return;
        // ponytail: a message that lands between a channel list being read
        // and applied is counted twice until the next refresh or mark.
        _counts = {..._counts, channelId: countOf(channelId) + 1};
        notifyListeners();
      case 'chat_message_deleted' || 'chat_channel_changed' || 'resync':
        unawaited(refresh());
    }
  }
}
