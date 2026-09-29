import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/chat_channel_keys_controller.dart';
import 'package:quark/controllers/chat_controller.dart';
import 'package:quark/controllers/chat_messages_controller.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark/models/chat_channel_keys.dart';
import 'package:quark/models/chat_message.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A [ChatMessagesController] that never touches the network or crypto: its
/// timeline is [fakeEntries], and [send] records what it was given.
class FakeChatMessages extends ChatMessagesController {
  /// A fake timeline for [channelId].
  FakeChatMessages(int channelId)
    : super(
        channelId: channelId,
        keys: ChatChannelKeysController(),
        crypto: () => null,
        events: const Stream.empty(),
        reconnects: const Stream.empty(),
      );

  /// What [entries] returns.
  List<ChatTimelineEntry> fakeEntries = const [];

  /// Runs on every [send]; throw from it to fail the send.
  Future<void> Function(String text)? onSend;

  /// Every text [send] was called with.
  final List<String> sent = [];

  /// Every message id [delete] was called with.
  final List<int> deleted = [];

  /// Every `messageId emoji` [toggleReaction] was called with.
  final List<String> reacted = [];

  /// How many times [open] ran.
  int opens = 0;

  /// Whether [dispose] ran.
  bool disposed = false;

  @override
  List<ChatTimelineEntry> get entries => fakeEntries;

  @override
  Future<void> open() async => opens++;

  @override
  Future<void> catchUp() async {}

  @override
  Future<void> loadOlder() async {}

  @override
  Future<void> send(String text) async {
    sent.add(text);
    await onSend?.call(text);
  }

  @override
  Future<void> delete(int messageId) async => deleted.add(messageId);

  @override
  Future<void> toggleReaction(int messageId, String emoji) async =>
      reacted.add('$messageId $emoji');

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

/// A Member's set, what everyone gets on `general`.
const memberSet = {
  ChatPermission.readMessages,
  ChatPermission.sendMessages,
  ChatPermission.addReactions,
};

/// Every permission, what a channel's creator gets.
final ownerSet = ChatPermission.values.toSet();

/// Channels: `general` (1, the default, as a Member) and `random` (2, owned).
final fakeChannels = [
  const ChatChannel(
    id: 1,
    name: 'general',
    isDefault: true,
    permissions: memberSet,
  ),
  ChatChannel(id: 2, name: 'random', isPrivate: true, permissions: ownerSet),
];

/// A [ChatController] wired to fakes, with every fake reachable.
///
/// Channel changes act on [channels] as the Quark would, and each records
/// itself in [calls]. [failWith], when set, is what the next change throws.
class FakeChat {
  /// Builds the fakes and the controller.
  FakeChat({
    List<ChatChannel>? channels,
    List<ChatMember>? members,
    this.otherChannels = const [],
    this.isAdmin = false,
    this.unlocked = true,
  }) : channels = [...(channels ?? fakeChannels)] {
    controller = ChatController(
      listChannels: () async => this.channels,
      listAllChannels: () async {
        calls.add('list all');
        return [...this.channels, ...otherChannels];
      },
      isAdmin: () => isAdmin,
      createChannel: (name, topic) async {
        calls.add('create $name "$topic"');
        _fail();
        final channel = ChatChannel(
          id: 10 + this.channels.length,
          name: name,
          topic: topic,
          isPrivate: true,
          permissions: ownerSet,
        );
        this.channels.add(channel);
        return channel;
      },
      updateChannel: (id, {required name, required topic}) async {
        calls.add('update $id $name "$topic"');
        _fail();
        final i = this.channels.indexWhere((c) => c.id == id);
        final old = this.channels[i];
        return this.channels[i] = ChatChannel(
          id: id,
          name: name,
          topic: topic,
          isDefault: old.isDefault,
          isPrivate: old.isPrivate,
          permissions: old.permissions,
        );
      },
      deleteChannel: (id) async {
        calls.add('delete $id');
        _fail();
        this.channels.removeWhere((c) => c.id == id);
      },
      removeMember: (id, {userId, groupId}) async {
        calls.add('remove $id user=$userId group=$groupId');
        _fail();
        // Leaving takes the channel off this account's list.
        if (userId == 7) this.channels.removeWhere((c) => c.id == id);
        return (members: const <ChatMember>[], event: leaveEvent);
      },
      ensureKeys: (id) async {
        calls.add('ensure keys $id');
        return false;
      },
      signMemberChange: (event, {userId, groupId, permissions}) async =>
          calls.add('sign ${event?.id} user=$userId $permissions'),
      listMembers: (_) async =>
          members ??
          [ChatMember(userId: 7, name: 'ada', permissions: ownerSet)],
      messagesFor: (id) =>
          opened[id] = FakeChatMessages(id)
            ..fakeEntries = entries[id] ?? const [],
      isUnlocked: () => unlocked,
      unlock: (password) async {
        if (password != 'right') throw Exception('wrong');
        unlocked = true;
        keys.notifyListeners();
      },
      isWaitingForKey: waiting.contains,
      keyChanges: keys,
      currentUserId: () => 7,
      events: events.stream,
      now: () => DateTime(2026, 9, 25, 12),
    );
  }

  /// The timeline each channel's fake starts with.
  final Map<int, List<ChatTimelineEntry>> entries = {};

  /// The channels the account can see, as the Quark holds them; replace
  /// them to change what the account may do, then fire
  /// `chat_channel_changed`.
  List<ChatChannel> channels;

  /// The controller under test.
  late final ChatController controller;

  /// For an admin, the channels they are not in.
  final List<ChatChannel> otherChannels;

  /// Whether the account is an admin.
  bool isAdmin;

  /// Every channel change and key call, in order.
  final List<String> calls = [];

  /// What the next channel change throws, then forgets.
  Object? failWith;

  /// The event a leave answers with.
  ChatChannelEvent? leaveEvent = ChatChannelEvent(
    id: 42,
    channelId: 2,
    kind: ChatChannelEvent.memberRemoved,
    actorId: 7,
    payload: '{"userId":7,"name":"ada"}',
    createdAt: DateTime.utc(2026, 9, 25),
  );

  void _fail() {
    final error = failWith;
    failWith = null;
    if (error != null) throw error;
  }

  /// Whether chat is unlocked.
  bool unlocked;

  /// Channels waiting for a key.
  final Set<int> waiting = {};

  /// Fires as the key controllers would.
  final ChangeNotifier keys = ChangeNotifier();

  /// The events socket.
  final StreamController<FileEvent> events = StreamController.broadcast();

  /// The newest timeline made for each channel.
  final Map<int, FakeChatMessages> opened = {};
}
