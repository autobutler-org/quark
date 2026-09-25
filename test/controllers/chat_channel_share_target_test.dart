import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/chat_channel_share_target.dart';
import 'package:quark/controllers/share_controller.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark/models/chat_channel_keys.dart';
import 'package:quark/models/path_grant.dart' show SharePrincipals;
import 'package:quark_widgets/quark_widgets.dart';

/// A channel's members through the share sheet's controller (#2422): who is
/// in, who manages, `general`'s everyone locked, and every change signed when
/// the Quark's event says what was asked.
void main() {
  const everyoneRow = ChatMember(
    groupId: 1,
    name: 'everyone',
    level: 'write',
    builtin: true,
  );
  const adaOwner = ChatMember(userId: 7, name: 'ada', level: 'owner');
  const bobWriter = ChatMember(userId: 8, name: 'bob', level: 'write');
  const design = ChatChannel(id: 2, name: 'design', level: 'owner');
  const general = ChatChannel(
    id: 1,
    name: 'general',
    isDefault: true,
    level: 'write',
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

  late List<String> calls;
  setUp(() => calls = []);

  ShareController controller(
    ChatChannel channel, {
    List<ChatMember> members = const [adaOwner, bobWriter],
    bool isAdmin = false,
    ChatChannelEvent? event,
  }) => ShareController(
    target: ChatChannelShareTarget(
      channel: channel,
      isAdmin: isAdmin,
      listMembers: (id) async {
        calls.add('list $id');
        return members;
      },
      setMember: (id, {userId, groupId, required level}) async {
        calls.add('set $id user=$userId group=$groupId $level');
        return (members: const [adaOwner], event: event);
      },
      removeMember: (id, {userId, groupId}) async {
        calls.add('remove $id user=$userId group=$groupId');
        return (members: const [adaOwner], event: event);
      },
      signMemberChange: (event, {userId, groupId, level}) async =>
          calls.add('sign ${event?.id} user=$userId level=$level'),
    ),
    selfUsername: 'ada',
    loadPrincipals: () async => const SharePrincipals(),
  );

  test('lists the members, none inherited, managed by an owner', () async {
    final c = controller(design);
    await c.load();

    expect(calls, ['list 2']);
    expect(c.canManage, isTrue);
    expect(c.grants.map((g) => (g.principal.name, g.level, g.inheritedFrom)), [
      ('ada', AccessLevel.owner, null),
      ('bob', AccessLevel.write, null),
    ]);
    expect(c.lockedKeys, {'user_7'}, reason: 'your own ownership');
  });

  test('a writer sees members but cannot manage; an admin can', () async {
    const writer = ChatChannel(id: 2, name: 'design', level: 'write');
    final c = controller(writer);
    await c.load();
    expect(c.canManage, isFalse);

    final admin = controller(
      const ChatChannel(id: 2, name: 'design'),
      isAdmin: true,
    );
    await admin.load();
    expect(admin.canManage, isTrue);
  });

  test("general's everyone row is locked, even for an admin", () async {
    final c = controller(general, members: const [everyoneRow], isAdmin: true);
    await c.load();

    expect(c.lockedKeys, {'group_1'});
    expect(c.principals, isEmpty);
  });

  test('adding signs the event it returns', () async {
    final c = controller(
      design,
      event: memberEvent(ChatChannelEvent.memberSet, {
        'userId': 8,
        'name': 'bob',
        'level': 'read',
      }),
    );
    await c.load();

    expect(await c.share(bob, AccessLevel.read), isNull);
    expect(calls.skip(1), [
      'set 2 user=8 group=null read',
      'sign 5 user=8 level=read',
    ]);
    expect(c.grants.single.principal.name, 'ada');
  });

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
    expect(calls.skip(1), [
      'remove 2 user=8 group=null',
      'sign 5 user=8 level=null',
    ]);
  });

  test('an event is only signed when it says what was asked', () {
    final removed = memberEvent(ChatChannelEvent.memberRemoved, {
      'userId': 8,
      'name': 'bob',
    });
    expect(removed.describesMemberChange(userId: 8), isTrue);
    expect(removed.describesMemberChange(userId: 9), isFalse);
    expect(removed.describesMemberChange(userId: 8, level: 'read'), isFalse);
    expect(removed.describesMemberChange(groupId: 8), isFalse);

    final set = memberEvent(ChatChannelEvent.memberSet, {
      'groupId': 3,
      'name': 'crew',
      'level': 'owner',
    });
    expect(set.describesMemberChange(groupId: 3, level: 'owner'), isTrue);
    expect(set.describesMemberChange(groupId: 3, level: 'write'), isFalse);
  });
}
