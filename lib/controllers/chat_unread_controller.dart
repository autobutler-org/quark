import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/chat_channels_service.dart';
import 'package:quark/services/chat_messages_service.dart';
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
/// - Side conversations (#4349): a channel's count also holds the unread
///   replies in branches the account is involved in, and [splits] keeps the
///   parts apart, with the replies in every other branch, for
///   `ChatUnreadMentionsController`. Only the Quark knows who is involved,
///   so a reply's `chat_message_created`, a branch's
///   `chat_read_marker_changed` and [markBranchRead] read the counts again.
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
    Future<ChatReadMarker> Function(int rootId, int messageId) markBranchRead =
        ChatMessagesService.markBranchRead,
    int? Function()? currentUserId,
    Stream<FileEvent>? events,
  }) : _listChannels = listChannels,
       _markRead = markRead,
       _markBranchRead = markBranchRead,
       _currentUserId =
           currentUserId ?? (() => AppSettings.instance.userId.value),
       _eventStream = events;

  /// The one the app uses.
  static final ChatUnreadController instance = ChatUnreadController();

  final Future<List<ChatChannel>> Function() _listChannels;
  final Future<ChatReadMarker> Function(int channelId, int messageId) _markRead;
  final Future<ChatReadMarker> Function(int rootId, int messageId)
  _markBranchRead;
  final int? Function() _currentUserId;
  final Stream<FileEvent>? _eventStream;
  StreamSubscription<FileEvent>? _events;

  Map<int, int> _counts = const {};

  /// Each channel's unread replies in branches the account is involved in,
  /// and in every other branch (#4349).
  Map<int, int> _branchCounts = const {};
  Map<int, int> _otherBranchCounts = const {};

  /// The channel on screen while this window is focused on it. Its count is
  /// hidden until the window leaves it.
  int? _viewingId;

  /// The newest message id sent or heard as each channel's marker.
  final Map<int, int> _markers = {};

  /// The newest reply id sent as each side conversation's marker, by root.
  final Map<int, int> _branchMarkers = {};

  /// How many unread messages channel [channelId] holds, the replies in
  /// branches the account is involved in included; zero for one never heard
  /// of, and zero for the channel [setViewing] is holding.
  int countOf(int channelId) => counts[channelId] ?? 0;

  /// Every channel's unread count, by channel id, as [countOf] gives it.
  Map<int, int> get counts => {
    for (final id in {..._counts.keys, ..._branchCounts.keys})
      id: isViewing(id) ? 0 : (_counts[id] ?? 0) + (_branchCounts[id] ?? 0),
  };

  /// Each channel with anything unread, in the channel itself or in any of
  /// its side conversations (#4349), with the parts apart. The channel
  /// [setViewing] is holding is here too: its side conversations are still
  /// drawn.
  Map<int, ChatUnreadSplit> get splits => {
    for (final id in {
      ..._counts.keys,
      ..._branchCounts.keys,
      ..._otherBranchCounts.keys,
    })
      if ((_counts[id] ?? 0) +
              (_branchCounts[id] ?? 0) +
              (_otherBranchCounts[id] ?? 0) >
          0)
        id: (
          channel: _counts[id] ?? 0,
          branches: _branchCounts[id] ?? 0,
          otherBranches: _otherBranchCounts[id] ?? 0,
        ),
  };

  /// Whether channel [channelId] is the one [setViewing] is holding, whose
  /// counts read as zero.
  bool isViewing(int channelId) => channelId == _viewingId;

  /// Whether any channel holds an unread message.
  bool get hasUnread => counts.values.any((count) => count > 0);

  /// The channel on screen, and whether this window is focused on it.
  ///
  /// While [focused] is true and [channelId] is set, that channel's count
  /// stays 0: the badge is hidden, and a message that arrives is not shown
  /// as unread. A null [channelId], or [focused] false, shows the count
  /// again, including messages that arrived in the meantime. A refresh
  /// while it is still focused stores the Quark's count and keeps hiding it.
  void setViewing(int? channelId, {required bool focused}) {
    final next = focused ? channelId : null;
    if (next == _viewingId) return;
    _viewingId = next;
    notifyListeners();
  }

  /// Reads every channel's count from the Quark.
  Future<void> refresh() async {
    _follow();
    try {
      setChannels(await _listChannels());
    } catch (e) {
      debugPrint('chat: unread counts not loaded: $e');
    }
  }

  /// Takes the counts and read markers from [channels], a list just loaded.
  /// A marker only moves forward, so one a refresh restores after the socket
  /// missed it never undoes a newer [markRead] still in flight (#3543).
  void setChannels(List<ChatChannel> channels) {
    _follow();
    _counts = {for (final c in channels) c.id: c.unreadCount};
    _branchCounts = {for (final c in channels) c.id: c.branchUnreadCount};
    _otherBranchCounts = {
      for (final c in channels) c.id: c.otherBranchUnreadCount,
    };
    for (final c in channels) {
      if (c.lastReadMessageId > 0) {
        _markers[c.id] = max(_markers[c.id] ?? 0, c.lastReadMessageId);
      }
    }
    notifyListeners();
  }

  /// Moves channel [channelId]'s read marker to message [messageId], unless
  /// the marker is already there or past it. A failure is forgotten, so the
  /// next call tries again.
  Future<void> markRead(int channelId, int messageId) =>
      _mark(_markers, channelId, messageId, () async {
        _apply(await _markRead(channelId, messageId));
      });

  /// Moves the read marker in the side conversation of message [rootId] to
  /// reply [messageId] (#4349), as [markRead] does for a channel, then reads
  /// the counts again: only the Quark knows what the branch added to its
  /// channel's.
  Future<void> markBranchRead(int rootId, int messageId) =>
      _mark(_branchMarkers, rootId, messageId, () async {
        await _markBranchRead(rootId, messageId);
        await refresh();
      });

  /// Sends marker [messageId] for [key] in [markers] with [send], unless it
  /// is already there or past it. A failure is forgotten, so the next call
  /// tries again.
  Future<void> _mark(
    Map<int, int> markers,
    int key,
    int messageId,
    Future<void> Function() send,
  ) async {
    _follow();
    final standing = markers[key];
    if (standing != null && messageId <= standing) return;
    markers[key] = messageId;
    try {
      await send();
    } catch (e) {
      debugPrint('chat: read marker not set for $key: $e');
      if (markers[key] != messageId) return;
      if (standing == null) {
        markers.remove(key);
      } else {
        markers[key] = standing;
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
        if (data is! Map<String, dynamic> || data['channelId'] is! num) return;
        final marker = ChatReadMarker.fromJson(data);
        if (marker.rootId == null) {
          _apply(marker);
        } else {
          unawaited(refresh());
        }
      case 'chat_message_created':
        if (data is! Map) return;
        // ponytail: every reply reads the channel list again, since only the
        // Quark knows who is involved in its branch. Send the involved
        // accounts with the event if a busy Quark makes that heavy.
        if (data['rootId'] != null) return unawaited(refresh());
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

/// A channel's unread counts kept apart (#4349): its own messages, the
/// replies in side conversations the account is involved in, and those in
/// every other side conversation.
typedef ChatUnreadSplit = ({int channel, int branches, int otherBranches});
