import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/chat_channel_share_target.dart';
import 'package:quark/controllers/share_controller.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark/models/chat_channel_keys.dart';
import 'package:quark/models/path_grant.dart' show SharePrincipals;
import 'package:quark_widgets/quark_widgets.dart';

/// A channel's members through the share sheet's controller (#2422): who is
/// in with which set, who manages, the rows the escalation bound locks,
/// `general`'s everyone locked, and every change signed when the Quark's
/// event says what was asked.
void main() {
  const read = ChatPermission.readMessages;
  const member = {
    ChatPermission.readMessages,
    ChatPermission.sendMessages,
    ChatPermission.addReactions,
  };
  const moderator = {
    ...member,
    ChatPermission.deleteMessages,
    ChatPermission.manageMembers,
  };
  final owner = ChatPermission.values.toSet();
  const everyoneRow = ChatMember(
    groupId: 1,
    name: 'everyone',
    permissions: member,
    builtin: true,
  );
  final adaOwner = ChatMember(userId: 7, name: 'ada', permissions: owner);
  const bobMember = ChatMember(userId: 8, name: 'bob', permissions: member);
  const cyModerator = ChatMember(userId: 9, name: 'cy', permissions: moderator);
  final design = ChatChannel(
    id: 2,
    name: 'design',
    permissions: owner,
    createdBy: 7,
  );
  final general = ChatChannel(
    id: 1,
    name: 'general',
    isDefault: true,
    permissions: owner,
  );
  const bob = PrincipalItem(kind: PrincipalKind.user, id: 8, name: 'bob');

  ChatChannelEvent memberEvent(String kind, Map<String, Object> payload) =>
      ChatChannelEvent(
        id: 5,
        channelId: 2,
        kind: kind,
        actorId: 7,
        payload: jsonEncode(payload),
        createdAt: DateTime.utc(2026, 9, 25),
      );

  String ids(Set<ChatPermission>? permissions) => permissions == null
      ? 'none'
      : [
          for (final p in ChatPermission.values)
            if (permissions.contains(p)) p.id,
        ].join(',');

  late List<String> calls;
  setUp(() => calls = []);

  ShareController controller(
    ChatChannel channel, {
    List<ChatMember>? members,
    bool isAdmin = false,
    int selfUserId = 7,
    ChatChannelEvent? event,
  }) => ShareController(
    target: ChatChannelShareTarget(
      channel: channel,
      isAdmin: isAdmin,
      selfUserId: selfUserId,
      listMembers: (id) async {
        calls.add('list $id');
        return members ?? [adaOwner, bobMember];
      },
      setMember: (id, {userId, groupId, required permissions}) async {
        calls.add('set $id user=$userId group=$groupId ${ids(permissions)}');
        return (members: [adaOwner], event: event);
      },
      removeMember: (id, {userId, groupId}) async {
        calls.add('remove $id user=$userId group=$groupId');
        return (members: [adaOwner], event: event);
      },
      signMemberChange: (event, {userId, groupId, permissions}) async =>
          calls.add('sign ${event?.id} user=$userId ${ids(permissions)}'),
    ),
    selfUsername: 'ada',
    loadPrincipals: () async => const SharePrincipals(),
  );

  test('lists the members with their sets, none inherited', () async {
    final c = controller(design);
    await c.load();

    expect(calls, ['list 2']);
    expect(c.canManage, isTrue);
    expect(c.heldPermissions, owner);
    expect(
      c.grants.map((g) => (g.principal.name, g.permissions, g.inheritedFrom)),
      [('ada', owner, null), ('bob', member, null)],
    );
    expect(c.lockedKeys, isEmpty, reason: 'ada holds manage_channel');
  });

  test('a member sees members but cannot manage; an admin can', () async {
    final c = controller(
      const ChatChannel(id: 2, name: 'design', permissions: member),
    );
    await c.load();
    expect(c.canManage, isFalse);

    final admin = controller(
      const ChatChannel(id: 2, name: 'design'),
      isAdmin: true,
    );
    await admin.load();
    expect(admin.canManage, isTrue);
    expect(admin.heldPermissions, owner);
    expect(admin.lockedKeys, isEmpty);
  });

  test('a moderator may change only a strict subset of itself', () async {
    final c = controller(
      ChatChannel(id: 2, name: 'design', permissions: moderator, createdBy: 7),
      members: [adaOwner, bobMember, cyModerator],
      selfUserId: 9,
    );
    await c.load();

    expect(c.canManage, isTrue);
    expect(c.lockedKeys, {'user_7', 'user_9'}, reason: 'the creator and cy');
    expect(c.principals, isEmpty);
  });

  test("general's everyone row is locked, even for an admin", () async {
    final c = controller(general, members: const [everyoneRow], isAdmin: true);
    await c.load();

    expect(c.lockedKeys, {'group_1'});
    expect(c.principals, isEmpty);
  });

  test('adding sends the whole set and signs the event', () async {
    final c = controller(
      design,
      event: memberEvent(ChatChannelEvent.memberSet, {
        'userId': 8,
        'name': 'bob',
        'permissions': ['read_messages'],
      }),
    );
    await c.load();

    expect(await c.sharePermissions(bob, {read}), isNull);
    expect(calls.skip(1), [
      'set 2 user=8 group=null read_messages',
      'sign 5 user=8 read_messages',
    ]);
    expect(c.grants.single.principal.name, 'ada');
  });

  test(
    'a demotion that drops read_messages is the key-rotating kind',
    () async {
      final c = controller(design);
      await c.load();

      expect(c.losesKey(bob, {ChatPermission.manageMembers}), isTrue);
      expect(c.losesKey(bob, {read}), isFalse);
      expect(c.losesKey(bob, null), isTrue, reason: 'removing bob');
      const newcomer = PrincipalItem(
        kind: PrincipalKind.user,
        id: 3,
        name: 'x',
      );
      expect(
        c.losesKey(newcomer, {ChatPermission.manageMembers}),
        isFalse,
        reason: 'a manage-only newcomer had no key to lose',
      );

      expect(
        await c.sharePermissions(bob, {ChatPermission.manageMembers}),
        isNull,
      );
      expect(calls.skip(1).first, 'set 2 user=8 group=null manage_members');
    },
  );

  test('removing signs its event; the Quark then asks for a new key', () async {
    final c = controller(
      design,
      event: memberEvent(ChatChannelEvent.memberRemoved, {
        'userId': 8,
        'name': 'bob',
      }),
    );
    await c.load();

    expect(await c.revoke(bob), isNull);
    expect(calls.skip(1), ['remove 2 user=8 group=null', 'sign 5 user=8 none']);
  });

  test('an event is only signed when it says what was asked', () {
    final removed = memberEvent(ChatChannelEvent.memberRemoved, {
      'userId': 8,
      'name': 'bob',
    });
    expect(removed.describesMemberChange(userId: 8), isTrue);
    expect(removed.describesMemberChange(userId: 9), isFalse);
    expect(
      removed.describesMemberChange(userId: 8, permissions: {read}),
      isFalse,
    );
    expect(removed.describesMemberChange(groupId: 8), isFalse);

    final set = memberEvent(ChatChannelEvent.memberSet, {
      'groupId': 3,
      'name': 'crew',
      'permissions': ['read_messages', 'manage_members'],
    });
    expect(
      set.describesMemberChange(
        groupId: 3,
        permissions: {read, ChatPermission.manageMembers},
      ),
      isTrue,
    );
    expect(set.describesMemberChange(groupId: 3, permissions: {read}), isFalse);
    expect(set.describesMemberChange(groupId: 3), isFalse);
  });
}
