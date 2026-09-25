import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/chat_controller.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark/models/chat_channel_keys.dart';
import 'package:quark/models/chat_message.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/fake_chat.dart';

ChatChannelEvent event(
  String kind,
  Map<String, Object> payload, {
  int actor = 7,
}) => ChatChannelEvent(
  id: 3,
  channelId: 1,
  kind: kind,
  actorId: actor,
  payload: jsonEncode(payload),
  createdAt: DateTime.utc(2026, 9, 25),
);

ChatMessage message(int id, {int author = 7}) => ChatMessage(
  id: id,
  channelId: 1,
  authorId: author,
  keyVersion: 1,
  ciphertext: null,
  createdAt: DateTime.utc(2026, 9, 25, 10, id),
);

void main() {
  test(
    'opens general for the bare path, an unknown id, and a stale link',
    () async {
      for (final requested in ['general', '999', 'nonsense']) {
        final chat = FakeChat();
        chat.controller.select(requested);
        await chat.controller.refresh();
        expect(chat.controller.selectedChannel?.id, 1, reason: requested);
        expect(chat.opened[1]!.opens, 1);
        chat.controller.dispose();
      }
    },
  );

  test('switching channels disposes the old timeline', () async {
    final chat = FakeChat();
    chat.controller.select('1');
    await chat.controller.refresh();
    final general = chat.opened[1]!;

    chat.controller.select('2');
    expect(general.disposed, isTrue);
    expect(chat.controller.selectedChannel?.name, 'random');
    expect(chat.opened[2]!.opens, 1);

    chat.controller.dispose();
    expect(chat.opened[2]!.disposed, isTrue);
  });

  test('a send shows pending at once and leaves once stored', () async {
    final chat = FakeChat();
    chat.controller.select('general');
    await chat.controller.refresh();
    final timeline = chat.opened[1]!;
    final gate = Completer<void>();
    timeline.onSend = (_) => gate.future;

    final sending = chat.controller.send('hi');
    expect(chat.controller.messageItems.first.body, 'hi');
    expect(chat.controller.messageItems.first.authorName, 'ada');
    expect(chat.controller.pending, hasLength(1));

    gate.complete();
    await sending;
    expect(timeline.sent, ['hi']);
    expect(chat.controller.pending, isEmpty);
    chat.controller.dispose();
  });

  test('a failed send is kept for retry or discard', () async {
    final chat = FakeChat();
    chat.controller.select('general');
    await chat.controller.refresh();
    final timeline = chat.opened[1]!;
    timeline.onSend = (_) async => throw const MessageException('offline');

    await chat.controller.send('hi');
    final failed = chat.controller.failedSends.single;
    expect(failed.text, 'hi');
    expect(Errors.message(failed.error, 'send the message'), 'Offline.');
    expect(chat.controller.messageItems.first.body, 'hi');

    timeline.onSend = null;
    await chat.controller.retry(failed.id);
    expect(timeline.sent, ['hi', 'hi']);
    expect(chat.controller.pending, isEmpty);

    timeline.onSend = (_) async => throw Exception('down');
    await chat.controller.send('again');
    chat.controller.discard(chat.controller.failedSends.single.id);
    expect(chat.controller.pending, isEmpty);
    chat.controller.dispose();
  });

  test('locked chat opens nothing until unlocked', () async {
    final chat = FakeChat(unlocked: false);
    chat.controller.select('general');
    await chat.controller.refresh();
    expect(chat.controller.isLocked, isTrue);
    expect(chat.opened[1]!.opens, 0);

    await chat.controller.unlock('wrong');
    expect(chat.controller.unlockError, isNotNull);
    expect(chat.controller.isLocked, isTrue);

    await chat.controller.unlock('right');
    expect(chat.controller.isLocked, isFalse);
    expect(chat.controller.unlockError, isNull);
    expect(chat.opened[1]!.opens, 1);
    chat.controller.dispose();
  });

  test('waiting for a key or read-only closes the composer', () async {
    final chat = FakeChat(
      channels: const [
        ChatChannel(id: 1, name: 'general', isDefault: true, level: 'write'),
        ChatChannel(id: 2, name: 'news', level: 'read'),
      ],
    );
    chat.controller.select('general');
    await chat.controller.refresh();
    expect(chat.controller.composerDisabledReason, isNull);

    chat.waiting.add(1);
    chat.keys.notifyListeners();
    expect(chat.controller.isWaitingForKey, isTrue);
    expect(chat.controller.composerDisabledReason, contains('key'));

    chat.controller.select('2');
    expect(chat.controller.composerDisabledReason, contains('read'));
    chat.controller.dispose();
  });

  test('maps the timeline newest first, with every state', () async {
    final chat = FakeChat();
    chat.controller.select('general');
    await chat.controller.refresh();
    chat.opened[1]!.fakeEntries = [
      ChatTimelineSystem(
        event: event(ChatChannelEvent.keyCreated, {'version': 1}),
        isVerified: true,
      ),
      ChatTimelineMessage(
        message: message(1),
        state: ChatMessageState.ready,
        text: 'one',
      ),
      ChatTimelineMessage(
        message: message(2, author: 9),
        state: ChatMessageState.waiting,
      ),
      ChatTimelineMessage(
        message: message(3),
        state: ChatMessageState.unreadable,
      ),
      ChatTimelineMessage(message: message(4), state: ChatMessageState.deleted),
    ];

    final items = chat.controller.messageItems;
    expect(items.map((i) => i.kind), [
      ChatMessageKind.deleted,
      ChatMessageKind.text,
      ChatMessageKind.waitingForKey,
      ChatMessageKind.text,
      ChatMessageKind.system,
    ]);
    expect(items[1].body, ChatController.unreadableBody);
    expect(items[1].isUnverified, isTrue);
    expect(items[2].authorName, 'Former member');
    expect(items[3].body, 'one');
    expect(items[4].body, 'ada set up encryption for this channel');
    expect(items[4].id, 'event_3');
    chat.controller.dispose();
  });

  test('system lines read as sentences', () {
    String name(int id) => {7: 'ada', 9: 'bob'}[id] ?? 'Former member';
    String say(ChatChannelEvent e) => ChatController.systemSentence(e, name);

    expect(
      say(
        event(ChatChannelEvent.memberSet, {
          'userId': 9,
          'name': 'bob',
          'level': 'write',
        }),
      ),
      'ada gave bob write access',
    );
    expect(
      say(
        event(ChatChannelEvent.memberRemoved, {
          'userId': 9,
          'name': 'bob',
        }, actor: 9),
      ),
      'bob left the channel',
    );
    expect(
      say(
        event(ChatChannelEvent.memberRemoved, {'groupId': 4, 'name': 'family'}),
      ),
      'ada removed family',
    );
    expect(
      say(event(ChatChannelEvent.keyCreated, {'version': 2})),
      'ada made a new key for this channel',
    );
  });

  test('chat_channel_changed reloads the channels', () async {
    var calls = 0;
    final chat = FakeChat();
    chat.controller.select('general');
    await chat.controller.refresh();
    chat.controller.addListener(() => calls++);

    chat.events.add(
      const FileEvent(
        kind: 'chat_channel_changed',
        path: '',
        data: {'channelId': 1},
      ),
    );
    await pumpEventQueue();
    expect(calls, greaterThan(0));
    chat.controller.dispose();
  });

  test('members map to the list, groups with their accounts', () async {
    final chat = FakeChat(
      members: const [
        ChatMember(userId: 7, name: 'ada', level: 'owner'),
        ChatMember(
          groupId: 4,
          name: 'family',
          level: 'write',
          users: [ChatMemberUser(id: 9, username: 'bob', avatarUpdatedAt: 5)],
        ),
      ],
    );
    chat.controller.select('general');
    await chat.controller.refresh();

    final items = chat.controller.memberItems;
    expect(items[0].level, AccessLevel.owner);
    expect(items[1].id, 'group_4');
    expect(items[1].isGroup, isTrue);
    expect(items[1].members.single.name, 'bob');
    expect(chat.controller.nameOf(9), 'bob');
    expect(chat.controller.avatarVersionOf(9), 5);

    chat.controller.toggleGroup('group_4');
    expect(chat.controller.expandedGroupIds, {'group_4'});
    chat.controller.dispose();
  });
}
