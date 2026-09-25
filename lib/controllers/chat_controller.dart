import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/chat_channel_keys_controller.dart';
import 'package:quark/controllers/chat_keys_controller.dart';
import 'package:quark/controllers/chat_messages_controller.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark/models/chat_channel_keys.dart';
import 'package:quark/models/chat_message.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/chat_channels_service.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Lists the channels the signed-in account belongs to.
typedef ListChatChannelsFn = Future<List<ChatChannel>> Function();

/// Lists one channel's members.
typedef ListChatMembersFn = Future<List<ChatMember>> Function(int channelId);

/// A message sent from this client that the Quark has not stored yet: shown
/// at once, and kept with its [error] when sending failed so it can be
/// retried.
@immutable
class ChatPendingSend {
  /// Builds a pending send.
  const ChatPendingSend({
    required this.id,
    required this.channelId,
    required this.text,
    required this.sentAt,
    this.error,
  });

  /// `pending_<n>`, unique within the controller.
  final String id;

  /// The channel it is going to.
  final int channelId;

  /// What was written.
  final String text;

  /// When it was written.
  final DateTime sentAt;

  /// Why the last attempt failed, for `Errors.message`; null while sending.
  final Object? error;

  /// Whether the last attempt failed.
  bool get failed => error != null;

  /// This send with [error] as its outcome.
  ChatPendingSend withError(Object? error) => ChatPendingSend(
    id: id,
    channelId: channelId,
    text: text,
    sentAt: sentAt,
    error: error,
  );
}

/// The chat page's state (#2421): the channels, the one open, its timeline,
/// its members, what is being sent, and whether chat is unlocked.
///
/// - [select] takes the channel id from the URL. An id that is not one of
///   [channels], `general`, or none, opens the default channel, so a stale
///   link lands somewhere rather than on an error. The page follows
///   [selectedChannel] back into the URL.
/// - Each open channel gets its own [ChatMessagesController], disposed when
///   another is picked, so plaintext never outlives the channel on screen.
/// - [send] shows a pending row at once. A failure keeps it, with its error,
///   for [retry] or [discard].
/// - `chat_channel_changed` reloads the channel list, and the members when it
///   names the open channel.
/// - While [isLocked] (on web after a reload) nothing is decrypted; [unlock]
///   takes the password and opens the channel.
///
/// Every collaborator has a real default; tests pass fakes.
class ChatController extends ChangeNotifier {
  /// Builds the controller. Call [select] with the URL's channel, then
  /// [refresh].
  ChatController({
    ListChatChannelsFn listChannels = ChatChannelsService.listChannels,
    ListChatMembersFn listMembers = ChatChannelsService.listMembers,
    ChatMessagesController Function(int channelId)? messagesFor,
    bool Function()? isUnlocked,
    Future<void> Function(String password)? unlock,
    bool Function(int channelId)? isWaitingForKey,
    Listenable? keyChanges,
    int? Function()? currentUserId,
    Stream<FileEvent>? events,
    DateTime Function()? now,
  }) : _listChannels = listChannels,
       _listMembers = listMembers,
       _messagesFor =
           messagesFor ??
           ((channelId) => ChatMessagesController(channelId: channelId)),
       _isUnlocked =
           isUnlocked ?? (() => ChatKeysController.instance.isUnlocked),
       _unlock = unlock ?? ChatKeysController.instance.unlock,
       _isWaitingForKey =
           isWaitingForKey ?? ChatChannelKeysController.instance.isWaiting,
       _keyChanges =
           keyChanges ??
           Listenable.merge([
             ChatKeysController.instance,
             ChatChannelKeysController.instance,
           ]),
       _currentUserId =
           currentUserId ?? (() => AppSettings.instance.userId.value),
       _now = now ?? DateTime.now {
    _wasUnlocked = _isUnlocked();
    _keyChanges.addListener(_onKeysChanged);
    _events = (events ?? EventsService.instance.events).listen(_onEvent);
  }

  /// The URL segment that means the default channel, as `/chat` redirects to.
  static const defaultChannelSlug = 'general';

  /// The body of a message whose key is there but whose ciphertext won't open
  /// under it.
  static const unreadableBody =
      "This message couldn't be opened. It may have been changed after it "
      'was sent.';

  final ListChatChannelsFn _listChannels;
  final ListChatMembersFn _listMembers;
  final ChatMessagesController Function(int channelId) _messagesFor;
  final bool Function() _isUnlocked;
  final Future<void> Function(String password) _unlock;
  final bool Function(int channelId) _isWaitingForKey;
  final Listenable _keyChanges;
  final int? Function() _currentUserId;
  final DateTime Function() _now;
  late final StreamSubscription<FileEvent> _events;

  String? _requested;
  List<ChatChannel> _channels = const [];
  bool _isLoadingChannels = false;
  Object? _channelsError;
  ChatChannel? _selected;
  ChatMessagesController? _messages;
  bool _isLoadingOlder = false;
  List<ChatMember> _members = const [];
  bool _isLoadingMembers = false;
  Object? _membersError;
  final Set<String> _expandedGroupIds = {};
  bool _isChannelListOpen = false;
  bool _isMemberListOpen = false;
  List<ChatPendingSend> _pending = const [];
  int _nextPending = 0;
  bool _wasUnlocked = false;
  bool _isUnlocking = false;
  Object? _unlockError;
  bool _disposed = false;

  /// The channels, `general` first.
  List<ChatChannel> get channels => _channels;

  /// Whether the channel list is loading.
  bool get isLoadingChannels => _isLoadingChannels;

  /// Why the channel list didn't load, for `Errors.message`.
  Object? get channelsError => _channelsError;

  /// The open channel, null until the list loads or when there are none.
  ChatChannel? get selectedChannel => _selected;

  /// The open channel's timeline, null with no channel open. Tests read it.
  ChatMessagesController? get messages => _messages;

  /// The open channel's members.
  List<ChatMember> get members => _members;

  /// Whether the members are loading.
  bool get isLoadingMembers => _isLoadingMembers;

  /// Why the members didn't load, for `Errors.message`.
  Object? get membersError => _membersError;

  /// The groups whose accounts the member list shows.
  Set<String> get expandedGroupIds => Set.unmodifiable(_expandedGroupIds);

  /// Whether the channel drawer is showing in the collapsed layout.
  bool get isChannelListOpen => _isChannelListOpen;

  /// Whether the member sheet is showing in the collapsed layout.
  bool get isMemberListOpen => _isMemberListOpen;

  /// Sends not yet stored, oldest first, across every channel.
  List<ChatPendingSend> get pending => _pending;

  /// The open channel's sends that failed, oldest first.
  List<ChatPendingSend> get failedSends => [
    for (final p in _pending)
      if (p.failed && p.channelId == _selected?.id) p,
  ];

  /// Whether chat needs the password before anything can be read: on web
  /// after a reload.
  bool get isLocked => !_isUnlocked();

  /// Whether [unlock] is running.
  bool get isUnlocking => _isUnlocking;

  /// Why the last [unlock] failed, for `Errors.message`.
  Object? get unlockError => _unlockError;

  /// Whether the open channel's messages are loading, first page or older.
  bool get isLoadingMessages =>
      (_messages?.isLoading ?? false) || _isLoadingOlder;

  /// Why the open channel's messages didn't load, for `Errors.message`.
  Object? get messagesError => _messages?.error;

  /// Whether older messages may exist.
  bool get hasOlderMessages => _messages?.hasOlder ?? false;

  /// Whether this account has no grant of the open channel's current key, so
  /// it can't send yet.
  bool get isWaitingForKey {
    final channel = _selected;
    return channel != null && _isWaitingForKey(channel.id);
  }

  /// Whether this account may post in the open channel.
  bool get canWrite => _selected?.canWrite ?? false;

  /// Why the composer is closed, as `QuarkMessageComposer.disabledReason`
  /// reads it; null when the account can post.
  String? get composerDisabledReason {
    if (_selected == null) return 'Pick a channel to write in it.';
    if (!canWrite) return 'You can read this channel but not write in it.';
    if (isWaitingForKey) {
      return 'Waiting for a member to share the key to this channel.';
    }
    return null;
  }

  /// The open channel's timeline for `QuarkMessageList`: newest first, sends
  /// not yet stored at the head.
  ///
  /// `ChatMessageItem` has no pending or failed kind, so a send in flight or
  /// failed is drawn as a plain text row; the page puts retry beside the
  /// composer.
  List<ChatMessageItem> get messageItems {
    final channel = _selected;
    final messages = _messages;
    if (channel == null || messages == null) return const [];
    final me = _currentUserId();
    return [
      for (final p in _pending.reversed)
        if (p.channelId == channel.id)
          ChatMessageItem(
            id: p.id,
            authorId: '${me ?? 0}',
            authorName: me == null ? 'You' : nameOf(me),
            sentAt: p.sentAt,
            body: p.text,
          ),
      for (final entry in messages.entries.reversed) itemFor(entry, nameOf),
    ];
  }

  /// The channels for `QuarkChannelList`.
  List<ChatChannelItem> get channelItems => [
    for (final c in _channels)
      ChatChannelItem(id: '${c.id}', name: c.name, isPrivate: c.isPrivate),
  ];

  /// The members for `QuarkMemberList`: accounts by their id, groups as
  /// `group_<id>` with their accounts under them.
  List<ChatMemberItem> get memberItems => [
    for (final m in _members)
      ChatMemberItem(
        id: m.userId != null ? '${m.userId}' : 'group_${m.groupId}',
        name: m.name,
        isGroup: m.groupId != null,
        level: AccessLevel.values.where((l) => l.name == m.level).firstOrNull,
        members: [
          for (final u in m.users)
            ChatMemberItem(id: '${u.id}', name: u.username),
        ],
      ),
  ];

  /// The name to show for account [userId]: from the members, or a stand-in
  /// for an account no longer in the channel.
  String nameOf(int userId) {
    if (userId == 0) return 'Deleted account';
    for (final m in _members) {
      if (m.userId == userId) return m.name;
      for (final u in m.users) {
        if (u.id == userId) return u.username;
      }
    }
    if (userId == _currentUserId()) {
      return AppSettings.instance.username ?? 'You';
    }
    return 'Former member';
  }

  /// Account [userId]'s profile picture version, from the members; null when
  /// it has none or isn't listed.
  int? avatarVersionOf(int userId) {
    for (final m in _members) {
      if (m.userId == userId) return m.avatarUpdatedAt;
      for (final u in m.users) {
        if (u.id == userId) return u.avatarUpdatedAt;
      }
    }
    return userId == _currentUserId()
        ? AppSettings.instance.avatarUpdatedAt.value
        : null;
  }

  /// Opens channel [channelId] from the URL: an id, [defaultChannelSlug], or
  /// null. One that isn't listed opens the default channel.
  void select(String? channelId) {
    _requested = channelId;
    _applySelection();
    _notify();
  }

  /// Reloads the channels, the open channel's members, and anything the
  /// timeline missed.
  Future<void> refresh() async {
    await _loadChannels();
    final messages = _messages;
    await Future.wait([
      _loadMembers(),
      if (messages != null && !isLocked) messages.catchUp(),
    ]);
  }

  /// Loads the page of messages before the oldest shown, or the first page
  /// again when that failed. Repeats while one is out are ignored, since the
  /// list asks on every scroll near the top.
  Future<void> loadOlder() async {
    final messages = _messages;
    if (messages == null || _isLoadingOlder) return;
    _isLoadingOlder = true;
    _notify();
    try {
      if (messages.error != null && messages.entries.isEmpty) {
        await messages.open();
      } else {
        await messages.loadOlder();
      }
    } finally {
      _isLoadingOlder = false;
      _notify();
    }
  }

  /// Sends [text] to the open channel, showing it as pending at once. A
  /// failure keeps it in [failedSends].
  Future<void> send(String text) async {
    final channel = _selected;
    if (channel == null) return;
    final pending = ChatPendingSend(
      id: 'pending_${_nextPending++}',
      channelId: channel.id,
      text: text,
      sentAt: _now(),
    );
    _pending = [..._pending, pending];
    _notify();
    await _deliver(pending);
  }

  /// Sends failed message [pendingId] again.
  Future<void> retry(String pendingId) async {
    final pending = _pending.where((p) => p.id == pendingId).firstOrNull;
    if (pending == null || !pending.failed) return;
    final again = pending.withError(null);
    _replacePending(pendingId, again);
    _notify();
    await _deliver(again);
  }

  /// Drops failed message [pendingId] without sending it.
  void discard(String pendingId) {
    _pending = [
      for (final p in _pending)
        if (p.id != pendingId) p,
    ];
    _notify();
  }

  /// Unlocks chat with the account [password]. A wrong one lands in
  /// [unlockError].
  Future<void> unlock(String password) async {
    if (_isUnlocking) return;
    _isUnlocking = true;
    _unlockError = null;
    _notify();
    try {
      await _unlock(password);
    } catch (e) {
      _unlockError = e;
    } finally {
      _isUnlocking = false;
      _notify();
    }
  }

  /// Flips the channel drawer of the collapsed layout.
  void toggleChannelList() {
    _isChannelListOpen = !_isChannelListOpen;
    _notify();
  }

  /// Closes the channel drawer, as picking a channel from it does.
  void closeChannelList() {
    if (!_isChannelListOpen) return;
    _isChannelListOpen = false;
    _notify();
  }

  /// Flips the member sheet of the collapsed layout.
  void toggleMemberList() {
    _isMemberListOpen = !_isMemberListOpen;
    _notify();
  }

  /// Expands or collapses group [id] in the member list.
  void toggleGroup(String id) {
    if (!_expandedGroupIds.remove(id)) _expandedGroupIds.add(id);
    _notify();
  }

  /// [entry] as `QuarkMessageList` draws it, with authors named by [nameOf].
  static ChatMessageItem itemFor(
    ChatTimelineEntry entry,
    String Function(int userId) nameOf,
  ) => switch (entry) {
    ChatTimelineMessage(:final message, :final state, :final text) =>
      ChatMessageItem(
        id: '${message.id}',
        authorId: '${message.authorId}',
        authorName: nameOf(message.authorId),
        sentAt: message.createdAt.toLocal(),
        body: switch (state) {
          ChatMessageState.ready => text ?? '',
          ChatMessageState.unreadable => unreadableBody,
          _ => '',
        },
        kind: switch (state) {
          ChatMessageState.ready ||
          ChatMessageState.unreadable => ChatMessageKind.text,
          ChatMessageState.waiting => ChatMessageKind.waitingForKey,
          ChatMessageState.deleted => ChatMessageKind.deleted,
        },
        isUnverified: state == ChatMessageState.unreadable,
      ),
    ChatTimelineSystem(:final event, :final isUnverified) => ChatMessageItem(
      id: 'event_${event.id}',
      authorId: '${event.actorId}',
      authorName: nameOf(event.actorId),
      sentAt: event.createdAt.toLocal(),
      body: systemSentence(event, nameOf),
      kind: ChatMessageKind.system,
      isUnverified: isUnverified,
    ),
  };

  /// The sentence a system line reads for [event]: who joined, left, changed
  /// level, or made a new channel key.
  static String systemSentence(
    ChatChannelEvent event,
    String Function(int userId) nameOf,
  ) {
    final actor = nameOf(event.actorId);
    Map<String, dynamic> data;
    try {
      data = event.data;
    } on Object {
      data = const {};
    }
    final name = data['name'] as String? ?? 'someone';
    final userId = (data['userId'] as num?)?.toInt();
    switch (event.kind) {
      case ChatChannelEvent.memberSet:
        final level = switch (data['level']) {
          'owner' => 'owner',
          'write' => 'write',
          _ => 'read',
        };
        return '$actor gave $name $level access';
      case ChatChannelEvent.memberRemoved:
        return userId != null && userId == event.actorId
            ? '$name left the channel'
            : '$actor removed $name';
      case ChatChannelEvent.keyCreated:
        final version = (data['version'] as num?)?.toInt() ?? 0;
        return version <= 1
            ? '$actor set up encryption for this channel'
            : '$actor made a new key for this channel';
      default:
        return 'The channel changed';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _events.cancel();
    _keyChanges.removeListener(_onKeysChanged);
    _closeMessages();
    super.dispose();
  }

  Future<void> _loadChannels() async {
    _isLoadingChannels = true;
    _notify();
    try {
      final channels = await _listChannels();
      if (_disposed) return;
      _channels = channels;
      _channelsError = null;
      _applySelection();
    } catch (e) {
      _channelsError = e;
    } finally {
      _isLoadingChannels = false;
      _notify();
    }
  }

  Future<void> _loadMembers() async {
    final channel = _selected;
    if (channel == null) return;
    _isLoadingMembers = true;
    _notify();
    try {
      final members = await _listMembers(channel.id);
      if (_disposed || _selected?.id != channel.id) return;
      _members = members;
      _membersError = null;
    } catch (e) {
      if (_selected?.id == channel.id) _membersError = e;
    } finally {
      _isLoadingMembers = false;
      _notify();
    }
  }

  /// Points [_selected] at the channel [_requested] names, or the default,
  /// and swaps the timeline when that is a different channel.
  void _applySelection() {
    final id = int.tryParse(_requested ?? '');
    final next =
        _channels.where((c) => c.id == id).firstOrNull ??
        _channels.where((c) => c.isDefault).firstOrNull ??
        _channels.firstOrNull;
    final changed = next?.id != _selected?.id;
    _selected = next;
    if (!changed) return;
    _closeMessages();
    _members = const [];
    _membersError = null;
    _expandedGroupIds.clear();
    if (next == null) return;
    final messages = _messagesFor(next.id)..addListener(_notify);
    _messages = messages;
    if (!isLocked) unawaited(messages.open());
    unawaited(_loadMembers());
  }

  void _closeMessages() {
    _messages
      ?..removeListener(_notify)
      ..dispose();
    _messages = null;
    _isLoadingOlder = false;
  }

  Future<void> _deliver(ChatPendingSend pending) async {
    final messages = _messages;
    if (messages == null || messages.channelId != pending.channelId) {
      // ponytail: a send only goes to the channel on screen; one left behind
      // by switching fails and waits for retry there.
      _replacePending(pending.id, pending.withError(StateError('left')));
      _notify();
      return;
    }
    try {
      await messages.send(pending.text);
      discard(pending.id);
    } catch (e) {
      _replacePending(pending.id, pending.withError(e));
      _notify();
    }
  }

  void _replacePending(String id, ChatPendingSend replacement) {
    _pending = [for (final p in _pending) p.id == id ? replacement : p];
  }

  /// Opens the channel when chat just unlocked, and repaints for key and
  /// waiting changes.
  void _onKeysChanged() {
    final unlocked = _isUnlocked();
    if (unlocked && !_wasUnlocked) {
      _unlockError = null;
      final messages = _messages;
      if (messages != null) unawaited(messages.open());
    }
    _wasUnlocked = unlocked;
    _notify();
  }

  void _onEvent(FileEvent event) {
    if (event.kind != 'chat_channel_changed') return;
    final data = event.data;
    final channelId = data is Map ? (data['channelId'] as num?)?.toInt() : null;
    unawaited(
      _loadChannels().then((_) {
        if (channelId == null || channelId == _selected?.id) {
          return _loadMembers();
        }
      }),
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
