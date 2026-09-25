import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/chat_channel_keys_controller.dart';
import 'package:quark/controllers/chat_controller.dart';
import 'package:quark/controllers/chat_messages_controller.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark/models/chat_message.dart';
import 'package:quark/services/events_service.dart';

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
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

/// Channels: `general` (1, the default) and `random` (2).
const fakeChannels = [
  ChatChannel(id: 1, name: 'general', isDefault: true, level: 'write'),
  ChatChannel(id: 2, name: 'random', isPrivate: true, level: 'owner'),
];

/// A [ChatController] wired to fakes, with every fake reachable.
class FakeChat {
  /// Builds the fakes and the controller.
  FakeChat({
    List<ChatChannel> channels = fakeChannels,
    List<ChatMember> members = const [
      ChatMember(userId: 7, name: 'ada', level: 'owner'),
    ],
    this.unlocked = true,
  }) {
    controller = ChatController(
      listChannels: () async => channels,
      listMembers: (_) async => members,
      messagesFor: (id) => opened[id] = FakeChatMessages(id),
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

  /// The controller under test.
  late final ChatController controller;

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
