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
  test('opens general for the bare path and the general slug', () async {
    for (final requested in [null, 'general']) {
      final chat = FakeChat();
      chat.controller.select(requested);
      await chat.controller.refresh();
      expect(chat.controller.selectedChannel?.id, 1, reason: requested);
      expect(chat.controller.isChannelMissing, isFalse);
      expect(chat.opened[1]!.opens, 1);
      chat.controller.dispose();
    }
  });

  // #2499: a link to a channel that doesn't exist, or that this account
  // isn't in, used to open general without a word.
  test('a link to a channel it cannot open says so, not general', () async {
    for (final requested in ['999', 'nonsense']) {
      final chat = FakeChat();
      chat.controller.select(requested);
      expect(
        chat.controller.isChannelMissing,
        isFalse,
        reason: 'not before the channels load',
      );
      await chat.controller.refresh();
      expect(chat.controller.selectedChannel, isNull, reason: requested);
      expect(chat.controller.isChannelMissing, isTrue, reason: requested);
      expect(chat.opened, isEmpty);
      expect(chat.controller.composerDisabledReason, isNotNull);

      chat.controller.select('general');
      expect(chat.controller.isChannelMissing, isFalse);
      expect(chat.controller.selectedChannel?.id, 1);
      chat.controller.dispose();
    }
  });

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

  test('the permission set arrives with the channel list', () async {
    final chat = FakeChat(
      channels: const [
        ChatChannel(
          id: 1,
          name: 'general',
          isDefault: true,
          permissions: memberSet,
        ),
        ChatChannel(
          id: 2,
          name: 'news',
          permissions: {ChatPermission.readMessages},
        ),
      ],
    );
    chat.controller.select('general');
    await chat.controller.refresh();
    expect(chat.controller.selectedPermissions, memberSet);
    expect(chat.controller.canSend, isTrue);
    expect(chat.controller.composerDisabledReason, isNull);

    chat.waiting.add(1);
    chat.keys.notifyListeners();
    expect(chat.controller.isWaitingForKey, isTrue);

    chat.controller.select('2');
    expect(chat.controller.selectedPermissions, {ChatPermission.readMessages});
    expect(chat.controller.canSend, isFalse);
    chat.controller.dispose();
  });

  test('a live downgrade disables sending in place', () async {
    final chat = FakeChat();
    chat.controller.select('general');
    await chat.controller.refresh();
    expect(chat.controller.canSend, isTrue);

    chat.channels = [
      const ChatChannel(
        id: 1,
        name: 'general',
        isDefault: true,
        permissions: {ChatPermission.readMessages},
      ),
      ...chat.channels.skip(1),
    ];
    chat.events.add(
      const FileEvent(
        kind: 'chat_channel_changed',
        path: '',
        data: {'channelId': 1},
      ),
    );
    await pumpEventQueue();

    expect(chat.controller.selectedChannel?.id, 1);
    expect(chat.controller.canSend, isFalse);
    expect(chat.opened[1]!.disposed, isFalse);
    chat.controller.dispose();
  });

  test('losing every permission on the open channel falls back', () async {
    final chat = FakeChat();
    chat.controller.select('2');
    await chat.controller.refresh();
    expect(chat.controller.selectedChannel?.name, 'random');

    chat.channels = chat.channels.take(1).toList();
    chat.events.add(
      const FileEvent(
        kind: 'chat_channel_changed',
        path: '',
        data: {'channelId': 2},
      ),
    );
    await pumpEventQueue();

    expect(chat.controller.selectedChannel?.name, 'general');
    expect(chat.opened[2]!.disposed, isTrue);
    chat.controller.dispose();
  });

  test('a manage-only set gets members, no timeline and no wait', () async {
    final chat = FakeChat(
      channels: const [
        ChatChannel(
          id: 1,
          name: 'general',
          isDefault: true,
          permissions: memberSet,
        ),
        ChatChannel(
          id: 3,
          name: 'ops',
          permissions: {ChatPermission.manageMembers},
        ),
      ],
    )..waiting.add(3);
    chat.controller.select('3');
    await chat.controller.refresh();

    expect(chat.controller.selectedChannel?.name, 'ops');
    expect(chat.controller.messages, isNull);
    expect(chat.opened.containsKey(3), isFalse);
    expect(chat.controller.isWaitingForKey, isFalse);
    expect(chat.controller.messageItems, isEmpty);
    expect(chat.controller.memberItems, isNotEmpty);

    // Given read_messages, the timeline opens in place.
    chat.channels = [
      chat.channels.first,
      const ChatChannel(
        id: 3,
        name: 'ops',
        permissions: {
          ChatPermission.readMessages,
          ChatPermission.manageMembers,
        },
      ),
    ];
    chat.events.add(
      const FileEvent(
        kind: 'chat_channel_changed',
        path: '',
        data: {'channelId': 3},
      ),
    );
    await pumpEventQueue();
    expect(chat.opened[3]!.opens, 1);
    expect(chat.controller.isWaitingForKey, isTrue);
    chat.controller.dispose();
  });

  test('deletes a message in the open channel', () async {
    final chat = FakeChat();
    chat.controller.select('general');
    await chat.controller.refresh();

    expect(await chat.controller.deleteMessage('12'), isNull);
    expect(await chat.controller.deleteMessage('pending_0'), isNull);
    expect(chat.opened[1]!.deleted, [12]);
    expect(chat.controller.currentUserKey, '7');
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
          'permissions': [
            'read_messages',
            'send_messages',
            'add_reactions',
            'delete_messages',
            'manage_reactions',
            'manage_members',
          ],
        }),
      ),
      'ada gave bob Moderator',
    );
    expect(
      say(
        event(ChatChannelEvent.memberSet, {
          'userId': 9,
          'name': 'bob',
          'permissions': ['manage_members'],
        }),
      ),
      'ada changed what bob can do',
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

  // #2563: deleting an account, or changing a profile picture, publishes
  // account_changed, which chat ignored, so the old picture stayed.
  test('account_changed reloads the members and channels', () async {
    final chat = FakeChat(
      members: [
        ChatMember(userId: 7, name: 'ada', permissions: ownerSet),
        const ChatMember(
          userId: 8,
          name: 'bob',
          permissions: memberSet,
          avatarUpdatedAt: 5,
        ),
      ],
    );
    chat.controller.select('2');
    await chat.controller.refresh();
    expect(chat.controller.avatarVersionOf(8), 5);
    final loads = chat.memberLoads;

    chat.members = [ChatMember(userId: 7, name: 'ada', permissions: ownerSet)];
    chat.channels.removeWhere((c) => c.id == 2);
    chat.channels.add(
      ChatChannel(
        id: 2,
        name: 'renamed',
        isPrivate: true,
        permissions: ownerSet,
      ),
    );
    chat.events.add(
      const FileEvent(kind: 'account_changed', path: '', data: {'userId': 8}),
    );
    await pumpEventQueue();

    expect(chat.memberLoads, loads + 1);
    expect(chat.controller.avatarVersionOf(8), isNull);
    expect(chat.controller.nameOf(8), 'Former member');
    expect(chat.controller.selectedChannel?.name, 'renamed');
    chat.controller.dispose();
  });

  // #2763: a resync means the socket dropped events, chat ones among them,
  // so the channels and the open channel's members are fetched again.
  test('resync reloads the members and channels', () async {
    final chat = FakeChat();
    chat.controller.select('2');
    await chat.controller.refresh();
    final loads = chat.memberLoads;

    chat.channels.removeWhere((c) => c.id == 2);
    chat.channels.add(
      ChatChannel(
        id: 2,
        name: 'renamed',
        isPrivate: true,
        permissions: ownerSet,
      ),
    );
    chat.events.add(const FileEvent(kind: 'resync', path: ''));
    await pumpEventQueue();

    expect(chat.memberLoads, loads + 1);
    expect(chat.controller.selectedChannel?.name, 'renamed');
    chat.controller.dispose();
  });

  test('members map to the list, groups with their accounts', () async {
    final chat = FakeChat(
      members: [
        ChatMember(userId: 7, name: 'ada', permissions: ownerSet),
        const ChatMember(
          groupId: 4,
          name: 'family',
          permissions: memberSet,
          users: [ChatMemberUser(id: 9, username: 'bob', avatarUpdatedAt: 5)],
        ),
      ],
    );
    chat.controller.select('general');
    await chat.controller.refresh();

    final items = chat.controller.memberItems;
    expect(items[0].permissions, ownerSet);
    expect(items[1].permissions, memberSet);
    expect(items[1].id, 'group_4');
    expect(items[1].isGroup, isTrue);
    expect(items[1].members.single.name, 'bob');
    expect(chat.controller.nameOf(9), 'bob');
    expect(chat.controller.avatarVersionOf(9), 5);

    chat.controller.toggleGroup('group_4');
    expect(chat.controller.expandedGroupIds, {'group_4'});
    chat.controller.dispose();
  });

  group('channel management (#2422)', () {
    test('creating lists the channel and makes its first key', () async {
      final chat = FakeChat();
      chat.controller.select('general');
      await chat.controller.refresh();

      final created = await chat.controller.createChannel('design', 'Mockups');

      expect(created?.name, 'design');
      expect(chat.calls, ['create design "Mockups"', 'ensure keys 12']);
      expect(chat.controller.channels.map((c) => c.name), contains('design'));
      expect(chat.controller.isSaving, isFalse);
      expect(chat.controller.saveError, isNull);
      chat.controller.dispose();
    });

    // #2501: a new channel was always private, with no say in it.
    test('a public channel gives everyone the Member set', () async {
      final chat = FakeChat();
      await chat.controller.refresh();

      final created = await chat.controller.createChannel(
        'design',
        '',
        isPrivate: false,
      );

      expect(created?.name, 'design');
      expect(chat.calls, [
        'create design ""',
        'ensure keys 12',
        'principals',
        'set 12 user=null group=1 Member',
        'sign 43 user=null $memberSet',
      ]);
      expect(chat.controller.saveError, isNull);
      chat.controller.dispose();
    });

    test('a channel that could not open to everyone still opens', () async {
      final chat = FakeChat()..setFailWith = const ApiException(500);
      await chat.controller.refresh();

      final channel = await chat.controller.createChannel(
        'design',
        '',
        isPrivate: false,
      );

      expect(channel?.name, 'design', reason: 'it was created');
      expect(chat.controller.saveError, isA<ApiException>());
      chat.controller.dispose();
    });

    test('a taken name reads as such', () async {
      final chat = FakeChat()..failWith = const ApiException(409);
      await chat.controller.refresh();

      expect(await chat.controller.createChannel('random', ''), isNull);
      expect(
        Errors.chatChannel(chat.controller.saveError, 'create the channel'),
        Errors.chatChannelNameTaken,
      );
      expect(chat.calls, ['create random ""'], reason: 'no key without one');

      chat.controller.clearSaveError();
      expect(chat.controller.saveError, isNull);
      chat.controller.dispose();
    });

    test('renaming changes the open channel', () async {
      final chat = FakeChat();
      chat.controller.select('2');
      await chat.controller.refresh();

      expect(await chat.controller.updateChannel('ideas', 'Anything'), isTrue);
      expect(chat.calls, ['update 2 ideas "Anything"']);
      expect(chat.controller.selectedChannel?.name, 'ideas');
      expect(chat.controller.selectedChannel?.topic, 'Anything');
      chat.controller.dispose();
    });

    test('deleting falls back to general', () async {
      final chat = FakeChat();
      chat.controller.select('2');
      await chat.controller.refresh();

      expect(await chat.controller.deleteChannel(), isTrue);
      expect(chat.calls, ['delete 2']);
      expect(chat.controller.selectedChannel?.id, 1);
      expect(chat.opened[2]!.disposed, isTrue);
      chat.controller.dispose();
    });

    test('leaving removes your row, signs it, and falls back', () async {
      final chat = FakeChat();
      chat.controller.select('2');
      await chat.controller.refresh();
      expect(chat.controller.canLeaveSelected, isTrue);

      expect(await chat.controller.leaveChannel(), isTrue);
      // The removal is what makes the Quark ask the members who stay to
      // rotate the key; the leaver signs the event from outside.
      expect(chat.calls, ['remove 2 user=7 group=null', 'sign 42 user=7 null']);
      expect(chat.controller.selectedChannel?.id, 1);
      chat.controller.dispose();
    });

    test('a refused leave keeps the channel and its reason', () async {
      final chat = FakeChat()
        ..failWith = const MessageException(
          'this would leave no one who can manage the channel',
        );
      chat.controller.select('2');
      await chat.controller.refresh();

      expect(await chat.controller.leaveChannel(), isFalse);
      expect(
        Errors.message(chat.controller.saveError, 'leave the channel'),
        'This would leave no one who can manage the channel.',
      );
      expect(chat.controller.selectedChannel?.id, 2);
      chat.controller.dispose();
    });

    test('general and group-only membership have no leave', () async {
      final chat = FakeChat(
        members: const [
          ChatMember(
            groupId: 1,
            name: 'everyone',
            permissions: memberSet,
            builtin: true,
          ),
        ],
      );
      chat.controller.select('general');
      await chat.controller.refresh();
      expect(chat.controller.canLeaveSelected, isFalse);

      chat.controller.select('2');
      await chat.controller.refresh();
      expect(
        chat.controller.canLeaveSelected,
        isFalse,
        reason: 'no row of your own to remove',
      );
      chat.controller.dispose();
    });

    test('manage_channel and manage_members gate settings apart', () async {
      final chat = FakeChat(
        channels: [
          ...fakeChannels,
          const ChatChannel(
            id: 3,
            name: 'ops',
            permissions: {ChatPermission.manageMembers},
          ),
        ],
      );
      chat.controller.select('general');
      await chat.controller.refresh();
      expect(chat.controller.canManageSelected, isFalse);
      expect(chat.controller.canManageMembers, isFalse);

      chat.controller.select('2');
      expect(chat.controller.canManageSelected, isTrue);
      expect(chat.controller.canManageMembers, isTrue);

      // A delegated manager changes members, not the channel.
      chat.controller.select('3');
      expect(chat.controller.canManageSelected, isFalse);
      expect(chat.controller.canManageMembers, isTrue);
      expect(chat.controller.managingPermissions, {
        ChatPermission.manageMembers,
      });

      final admin = FakeChat(isAdmin: true);
      admin.controller.select('general');
      await admin.controller.refresh();
      expect(admin.controller.canManageSelected, isTrue);
      expect(admin.controller.managingPermissions, ownerSet);
      chat.controller.dispose();
      admin.controller.dispose();
    });

    test(
      'an admin sees other channels apart, without their messages',
      () async {
        final chat = FakeChat(
          isAdmin: true,
          otherChannels: const [
            ChatChannel(id: 9, name: 'payroll', isPrivate: true),
          ],
        );
        chat.controller.select('9');
        await chat.controller.refresh();

        expect(chat.calls, ['list all']);
        expect(chat.controller.channelItems.map((c) => c.id), ['1', '2']);
        expect(chat.controller.otherChannelItems.map((c) => c.id), ['9']);
        expect(chat.controller.selectedChannel?.id, 9);
        expect(chat.opened[9], isNull, reason: 'never opened for reading');
        expect(chat.controller.messageItems, isEmpty);
        expect(chat.controller.canSend, isFalse);
        expect(chat.controller.selectedPermissions, isEmpty);
        expect(chat.controller.canManageSelected, isTrue);
        expect(chat.controller.canLeaveSelected, isFalse);
        chat.controller.dispose();
      },
    );

    test('removing a member signs the event and reloads', () async {
      final chat = FakeChat(
        members: [
          ChatMember(userId: 7, name: 'ada', permissions: ownerSet),
          const ChatMember(userId: 8, name: 'bob', permissions: memberSet),
          const ChatMember(
            groupId: 4,
            name: 'ops',
            permissions: {ChatPermission.manageMembers},
          ),
        ],
      );
      chat.controller.select('2');
      await chat.controller.refresh();
      chat.calls.clear();

      expect(chat.controller.memberReads('8'), isTrue);
      expect(chat.controller.memberReads('group_4'), isFalse);
      expect(await chat.controller.removeMember('8'), isNull);
      expect(await chat.controller.removeMember('group_4'), isNull);
      expect(chat.calls, [
        'remove 2 user=8 group=null',
        'sign 42 user=8 null',
        'remove 2 user=null group=4',
        'sign 42 user=null null',
      ]);
      chat.controller.dispose();
    });
  });

  // #2497: there was no way to message one person.
  group('message someone (#2497)', () {
    test('offers every other account, not groups or yourself', () async {
      final chat = FakeChat();
      await chat.controller.refresh();

      await chat.controller.loadPeople();

      expect(chat.controller.people.map((p) => p.name), ['bob', 'cy']);
      expect(chat.controller.peopleError, isNull);
      expect(chat.controller.isLoadingPeople, isFalse);
      chat.controller.dispose();
    });

    test('people that will not load say why', () async {
      final chat = FakeChat()..failWith = const ApiException(500);

      await chat.controller.loadPeople();

      expect(chat.controller.people, isEmpty);
      expect(chat.controller.peopleError, isA<ApiException>());
      chat.controller.dispose();
    });

    test('starts a private channel with them as a Member', () async {
      final chat = FakeChat();
      await chat.controller.refresh();
      await chat.controller.loadPeople();
      chat.calls.clear();

      final channel = await chat.controller.startConversation(8);

      expect(channel?.name, 'ada, bob');
      expect(chat.calls, [
        'create ada, bob ""',
        'ensure keys 12',
        'set 12 user=8 group=null Member',
        'sign 43 user=8 $memberSet',
      ]);
      chat.controller.dispose();
    });

    test('opens the conversation you already have', () async {
      final chat = FakeChat(
        channels: [
          ...fakeChannels,
          ChatChannel(
            id: 5,
            name: 'Bob, Ada',
            isPrivate: true,
            permissions: ownerSet,
          ),
          ChatChannel(
            id: 6,
            name: 'ada, bob',
            isPrivate: true,
            permissions: ownerSet,
          ),
        ],
      );
      await chat.controller.refresh();
      await chat.controller.loadPeople();
      chat.calls.clear();

      final channel = await chat.controller.startConversation(8);

      expect(channel?.id, 6);
      expect(chat.calls, isEmpty);
      chat.controller.dispose();
    });
  });

  group('encryption status (#2495)', () {
    ChatTimelineSystem key(int version, {bool verified = true, int id = 3}) =>
        ChatTimelineSystem(
          event: ChatChannelEvent(
            id: id,
            channelId: 1,
            kind: ChatChannelEvent.keyCreated,
            actorId: 7,
            payload: jsonEncode({'version': version}),
            createdAt: DateTime.utc(2026, 9, 25, 9, id),
          ),
          isVerified: verified,
        );

    Future<FakeChat> open(List<ChatTimelineEntry> entries) async {
      final chat = FakeChat()..entries[1] = entries;
      chat.controller.select('general');
      await chat.controller.refresh();
      return chat;
    }

    test('a healthy channel has nothing to say', () async {
      final chat = await open([
        key(1),
        ChatTimelineMessage(
          message: message(1),
          state: ChatMessageState.ready,
          text: 'hi',
        ),
      ]);
      expect(chat.controller.encryptionStatus, isNull);
      chat.controller.dispose();
    });

    test('waiting for the key comes first', () async {
      final chat = FakeChat()
        ..waiting.add(1)
        ..entries[1] = [key(1, verified: false)];
      chat.controller.select('general');
      await chat.controller.refresh();
      expect(
        chat.controller.encryptionStatus,
        ChatEncryptionStatus.waitingForKey,
      );
      chat.controller.dispose();
    });

    test(
      'an unverified current key says so; a later good one clears it',
      () async {
        final chat = await open([key(1), key(2, verified: false, id: 4)]);
        expect(
          chat.controller.encryptionStatus,
          ChatEncryptionStatus.unverifiedKey,
        );

        chat.opened[1]!.fakeEntries = [
          key(1),
          key(2, verified: false, id: 4),
          key(3, id: 5),
        ];
        expect(chat.controller.encryptionStatus, isNull);
        chat.controller.dispose();
      },
    );

    test('older messages without a key read as hidden history', () async {
      final chat = await open([
        ChatTimelineMessage(
          message: message(1),
          state: ChatMessageState.waiting,
        ),
        ChatTimelineMessage(
          message: message(2),
          state: ChatMessageState.ready,
          text: 'new',
        ),
      ]);
      expect(
        chat.controller.encryptionStatus,
        ChatEncryptionStatus.unreadableHistory,
      );
      chat.controller.dispose();
    });

    test('a manage-only channel never waits or warns', () async {
      final chat =
          FakeChat(
              channels: const [
                ChatChannel(
                  id: 3,
                  name: 'ops',
                  permissions: {ChatPermission.manageMembers},
                ),
              ],
            )
            ..waiting.add(3)
            ..entries[3] = [key(1, verified: false)];
      chat.controller.select('3');
      await chat.controller.refresh();
      expect(chat.controller.encryptionStatus, isNull);
      chat.controller.dispose();
    });

    test('key lines are marked as encryption events', () async {
      final chat = await open([
        key(1),
        ChatTimelineSystem(
          event: event(ChatChannelEvent.memberRemoved, {'name': 'bob'}),
          isVerified: true,
        ),
      ]);
      final items = chat.controller.messageItems;
      expect(items.map((i) => i.isEncryptionEvent), [false, true]);
      chat.controller.dispose();
    });

    test('check again asks for the key and reports while it runs', () async {
      final chat = FakeChat()..waiting.add(1);
      chat.controller.select('general');
      await chat.controller.refresh();
      chat.calls.clear();

      final checking = chat.controller.checkKey();
      expect(chat.controller.isCheckingKey, isTrue);
      await checking;
      expect(chat.controller.isCheckingKey, isFalse);
      expect(chat.calls, ['ensure keys 1']);
      chat.controller.dispose();
    });
  });

  group('on-device search (#2429)', () {
    Future<FakeChat> openGeneral() async {
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
          text: 'Lunch at noon?',
        ),
        ChatTimelineMessage(
          message: message(2, author: 9),
          state: ChatMessageState.waiting,
        ),
        ChatTimelineMessage(
          message: message(3),
          state: ChatMessageState.unreadable,
        ),
        ChatTimelineMessage(
          message: message(4),
          state: ChatMessageState.deleted,
        ),
        ChatTimelineMessage(
          message: message(5),
          state: ChatMessageState.ready,
          text: 'Bring the lunch boxes',
        ),
        ChatTimelineMessage(
          message: message(6),
          state: ChatMessageState.ready,
          text: 'See you there',
        ),
      ];
      return chat;
    }

    test('finds a loaded message whatever its case, newest first', () async {
      final chat = await openGeneral();
      final c = chat.controller;
      expect(c.canSearch, isTrue);

      c
        ..toggleSearch()
        ..search('  LUNCH ');

      expect(c.isSearching, isTrue);
      expect(c.searchQuery, '  LUNCH ');
      expect(c.searchMatchCount, 2);
      expect(c.messageItems.map((i) => i.id), ['5', '1']);
      c.dispose();
    });

    test('searches only text it has decrypted, and no pending send', () async {
      final chat = await openGeneral();
      final c = chat.controller;
      final sending = Completer<void>();
      chat.opened[1]!.onSend = (_) => sending.future;
      unawaited(c.send('lunch is pending'));
      expect(c.messageItems.first.body, 'lunch is pending');

      c
        ..toggleSearch()
        // Every row that isn't ready text: the system line's sentence, the
        // waiting author's name and the unreadable and deleted bodies.
        ..search('e');

      expect(c.messageItems.map((i) => i.kind).toSet(), {ChatMessageKind.text});
      expect(c.messageItems.map((i) => i.id), ['6', '5']);
      sending.complete();
      await pumpEventQueue();
      c.dispose();
    });

    test('a blank query shows the whole timeline and counts nothing', () async {
      final chat = await openGeneral();
      final c = chat.controller;
      final all = c.messageItems.length;

      expect(c.searchMatchCount, isNull);
      c.toggleSearch();
      expect(c.searchMatchCount, isNull);
      expect(c.messageItems, hasLength(all));
      c.search('   ');
      expect(c.searchMatchCount, isNull);
      expect(c.messageItems, hasLength(all));

      c.search('nothing says this');
      expect(c.searchMatchCount, 0);
      expect(c.messageItems, isEmpty);
      c.dispose();
    });

    test('closing search forgets the query', () async {
      final chat = await openGeneral();
      final c = chat.controller
        ..toggleSearch()
        ..search('lunch')
        ..toggleSearch();

      expect(c.isSearching, isFalse);
      expect(c.searchQuery, isEmpty);
      expect(c.searchMatchCount, isNull);
      c.dispose();
    });

    test('switching channels drops the search and its query', () async {
      final chat = await openGeneral();
      final c = chat.controller
        ..toggleSearch()
        ..search('lunch')
        ..select('2');

      expect(c.selectedChannel?.id, 2);
      expect(c.isSearching, isFalse);
      expect(c.searchQuery, isEmpty);
      c.dispose();
    });

    test('a channel you left is no longer searched', () async {
      final chat = FakeChat();
      final c = chat.controller..select('2');
      await c.refresh();
      final random = chat.opened[2]!
        ..fakeEntries = [
          ChatTimelineMessage(
            message: message(1),
            state: ChatMessageState.ready,
            text: 'the secret plan',
          ),
        ];
      c
        ..toggleSearch()
        ..search('secret');
      expect(c.searchMatchCount, 1);

      expect(await c.leaveChannel(), isTrue);

      expect(random.disposed, isTrue);
      expect(c.selectedChannel?.id, 1);
      expect(c.isSearching, isFalse);
      c
        ..toggleSearch()
        ..search('secret');
      expect(c.searchMatchCount, 0);
      expect(c.messageItems, isEmpty);
      c.dispose();
    });

    test('searching asks the Quark for nothing', () async {
      final chat = await openGeneral();
      final c = chat.controller;
      final calls = [...chat.calls];
      final memberLoads = chat.memberLoads;

      c
        ..toggleSearch()
        ..search('lunch');
      expect(c.messageItems, hasLength(2));
      c.toggleSearch();
      await pumpEventQueue();

      expect(chat.calls, calls);
      expect(chat.memberLoads, memberLoads);
      expect(chat.opened[1]!.opens, 1);
      expect(chat.opened[1]!.sent, isEmpty);
      c.dispose();
    });

    test('locking drops the search and its query', () async {
      final chat = await openGeneral();
      final c = chat.controller
        ..toggleSearch()
        ..search('lunch');

      chat.unlocked = false;
      chat.keys.notifyListeners();

      expect(c.canSearch, isFalse);
      expect(c.isSearching, isFalse);
      expect(c.searchQuery, isEmpty);
      c.toggleSearch();
      expect(c.isSearching, isFalse);
      c.dispose();
    });

    test('there is nothing to search while locked or without a timeline', () {
      final locked = FakeChat(unlocked: false);
      locked.controller.select('general');
      expect(locked.controller.canSearch, isFalse);
      locked.controller.dispose();

      final none = FakeChat();
      expect(none.controller.canSearch, isFalse);
      none.controller.dispose();
    });
  });
}
