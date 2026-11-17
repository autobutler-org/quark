import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/chat_unread_controller.dart';
import 'package:quark/controllers/chat_unread_mentions_controller.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark/models/chat_message.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Unread mentions in channels that are not open (#3157), over a fake Quark
/// whose ciphertext is the message's text. The signed-in account is ada (7).
void main() {
  const read = {ChatPermission.readMessages};
  late ChatUnreadController unread;
  late ChangeNotifier keys;
  late Map<int, List<ChatMessage>> messages;
  late Set<int> keyless;
  late List<String> calls;
  late bool unlocked;
  Object? failWith;
  var nextId = 1;

  ChatMessage message(
    String text, {
    int channel = 1,
    int author = 8,
    int version = 1,
    bool deleted = false,
  }) => ChatMessage(
    id: nextId++,
    channelId: channel,
    authorId: author,
    keyVersion: version,
    ciphertext: deleted ? null : utf8.encode(text),
    createdAt: DateTime.utc(2026, 10, 11),
    deletedAt: deleted ? DateTime.utc(2026, 10, 11) : null,
  );

  ChatUnreadMentionsController build() => ChatUnreadMentionsController(
    unread: unread,
    ensureKeys: (channelId) async {
      calls.add('keys $channelId');
      return false;
    },
    listMembers: (channelId) async => const [
      ChatMember(userId: 7, name: 'ada', permissions: read),
      ChatMember(userId: 8, name: 'bob', permissions: read),
      ChatMember(userId: 9, name: 'ada-marie', permissions: read),
      // cy holds mention_everyone through a group, not a row of her own.
      ChatMember(
        groupId: 3,
        name: 'mods',
        permissions: {
          ChatPermission.readMessages,
          ChatPermission.mentionEveryone,
        },
        users: [ChatMemberUser(id: 10, username: 'cy')],
      ),
    ],
    fetchMessages: (channelId, {limit}) async {
      calls.add('messages $channelId');
      final error = failWith;
      if (error != null) throw error;
      return messages[channelId] ?? const [];
    },
    openMessage: (m) => keyless.contains(m.keyVersion)
        ? null
        : utf8.decode(m.ciphertext ?? const []),
    isUnlocked: () => unlocked,
    keyChanges: keys,
    currentUserId: () => 7,
  );

  void setUnread(Map<int, int> counts) => unread.setChannels([
    for (final e in counts.entries)
      ChatChannel(id: e.key, name: 'c${e.key}', unreadCount: e.value),
  ]);

  setUp(() {
    unread = ChatUnreadController(
      listChannels: () async => const [],
      markRead: (channelId, messageId) async => ChatReadMarker(
        channelId: channelId,
        lastReadMessageId: messageId,
        unreadCount: 0,
      ),
      currentUserId: () => 7,
      events: const Stream<FileEvent>.empty(),
    );
    keys = ChangeNotifier();
    messages = {};
    keyless = {};
    calls = [];
    unlocked = true;
    failWith = null;
  });

  tearDown(() {
    unread.dispose();
    keys.dispose();
  });

  test('counts the unread messages that mention the account', () async {
    messages[1] = [
      message('@ada an old one, already read'),
      message('hey @ada'),
      message('@ada mine', author: 7),
      message('@ada gone', deleted: true),
      message('@bob and @ada-marie, not you'),
      message('@Ada again'),
    ];
    final mentions = build();
    var notified = 0;
    mentions.addListener(() => notified++);

    // Three unread: the newest three someone else wrote and nobody deleted.
    setUnread({1: 3, 2: 0});
    await pumpEventQueue();

    expect(mentions.countOf(1), 2);
    expect(mentions.countOf(2), 0);
    expect(notified, 1);
    expect(calls, ['keys 1', 'messages 1'], reason: 'channel 2 has no unread');
    mentions.dispose();
  });

  // #4293: @everyone counts only from an author holding mention_everyone.
  test('counts @everyone from an author allowed to use it', () async {
    messages[1] = [
      message('@everyone from cy', author: 10),
      message('@everyone from bob, who may not', author: 8),
      message('@everyone_else from cy', author: 10),
    ];
    final mentions = build();

    setUnread({1: 3});
    await pumpEventQueue();

    expect(mentions.countOf(1), 1);
    mentions.dispose();
  });

  test('reads a channel again only when its unread count moves', () async {
    messages[1] = [message('hey @ada')];
    final mentions = build();
    setUnread({1: 1});
    await pumpEventQueue();
    setUnread({1: 1});
    keys.notifyListeners();
    await pumpEventQueue();
    expect(calls, ['keys 1', 'messages 1']);

    messages[1] = [...messages[1]!, message('@ada once more')];
    setUnread({1: 2});
    await pumpEventQueue();
    expect(mentions.countOf(1), 2);

    // Read on any device: the count goes with the unread count.
    setUnread({1: 0});
    expect(mentions.countOf(1), 0);
    mentions.dispose();
  });

  test('reads nothing while chat is locked, and reads on unlock', () async {
    messages[1] = [message('hey @ada')];
    unlocked = false;
    final mentions = build();
    setUnread({1: 1});
    await pumpEventQueue();
    expect(calls, isEmpty);
    expect(mentions.countOf(1), 0);

    unlocked = true;
    keys.notifyListeners();
    await pumpEventQueue();
    expect(mentions.countOf(1), 1);

    unlocked = false;
    keys.notifyListeners();
    expect(mentions.countOf(1), 0);
    mentions.dispose();
  });

  test('a message waiting for its key is counted once it opens', () async {
    messages[1] = [message('hey @ada', version: 2), message('hello')];
    keyless = {2};
    final mentions = build();
    setUnread({1: 2});
    await pumpEventQueue();
    expect(mentions.countOf(1), 0);

    // Some other key lands: nothing to read again.
    keys.notifyListeners();
    await pumpEventQueue();
    expect(calls, ['keys 1', 'messages 1']);

    keyless = {};
    keys.notifyListeners();
    await pumpEventQueue();
    expect(mentions.countOf(1), 1);
    mentions.dispose();
  });

  test('a channel that fails to load keeps its count', () async {
    messages[1] = [message('hey @ada')];
    final mentions = build();
    setUnread({1: 1});
    await pumpEventQueue();

    failWith = Exception('offline');
    setUnread({1: 2});
    await pumpEventQueue();

    expect(mentions.countOf(1), 1);
    mentions.dispose();
  });
}
