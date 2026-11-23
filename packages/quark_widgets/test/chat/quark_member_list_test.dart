import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// A channel's member list (#2420): accounts with avatars, groups that expand
/// when the caller says so, and each state on its own.
void main() {
  final members = [
    ChatMemberItem(
      id: 'ada',
      name: 'Ada Lovelace',
      permissions: ChatPermissionPreset.owner.permissions,
    ),
    ChatMemberItem(
      id: 'family',
      name: 'Family',
      isGroup: true,
      permissions: ChatPermissionPreset.member.permissions,
      members: const [
        ChatMemberItem(id: 'bob', name: 'Bob'),
        ChatMemberItem(id: 'cy', name: 'Cy'),
      ],
    ),
    ChatMemberItem(
      id: 'dee',
      name: 'Dee',
      permissions: ChatPermissionPreset.viewer.permissions,
    ),
    const ChatMemberItem(
      id: 'eve',
      name: 'Eve',
      permissions: {ChatPermission.manageMembers},
    ),
  ];

  testWidgets('shows a spinner while loading and no rows', (tester) async {
    await pumpAt(tester, QuarkMemberList(members: members, isLoading: true));

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.byKey(const ValueKey('member_row_ada')), findsNothing);
    expect(find.text('No members yet'), findsNothing);
  });

  testWidgets('renders the error the caller handed it', (tester) async {
    await pumpAt(
      tester,
      QuarkMemberList(members: members, error: "Couldn't load members."),
    );

    expect(find.text("Couldn't load members."), findsOneWidget);
    expect(find.byKey(const ValueKey('member_row_ada')), findsNothing);
  });

  testWidgets('shows the empty copy when there are no members', (tester) async {
    await pumpAt(tester, const QuarkMemberList(members: []));

    expect(find.text('No members yet'), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
  });

  testBothViewports('renders each member with its preset, groups collapsed', (
    tester,
    size,
  ) async {
    await pumpAt(tester, QuarkMemberList(members: members), size: size);

    for (final member in members) {
      expect(find.byKey(ValueKey('member_row_${member.id}')), findsOneWidget);
    }
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Member'), findsOneWidget);
    expect(find.text('Viewer'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.byKey(const ValueKey('member_row_family_bob')), findsNothing);
    expect(find.byKey(const ValueKey('avatar_ada')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports the group that was tapped, not accounts', (
    tester,
  ) async {
    final toggled = <String>[];
    await pumpAt(
      tester,
      QuarkMemberList(
        members: members,
        expandedIds: const {'family'},
        onToggleExpanded: toggled.add,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('member_row_ada')));
    await tester.tap(find.byKey(const ValueKey('member_row_family_bob')));
    await tester.tap(find.byKey(const ValueKey('member_row_family')));
    await tester.pump();

    expect(toggled, ['family']);
  });

  testWidgets('hands account ids to the avatar builder', (tester) async {
    final ids = <String>[];
    await pumpAt(
      tester,
      QuarkMemberList(
        members: members,
        expandedIds: const {'family'},
        avatarBuilder: (context, userId) {
          ids.add(userId);
          return const SizedBox();
        },
      ),
    );

    expect(ids, ['ada', 'bob', 'cy', 'dee', 'eve']);
    expect(find.byKey(const ValueKey('member_row_family_bob')), findsOneWidget);
    expect(find.byKey(const ValueKey('member_row_family_cy')), findsOneWidget);
  });

  testBothViewports('offers add and remove to a member manager', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      QuarkMemberList(
        members: members,
        permissions: ChatPermissionPreset.moderator.permissions,
        onAddMembers: () => events.add('add'),
        onRemove: (id) => events.add('remove $id'),
      ),
      size: size,
    );

    await tester.tap(find.byKey(const ValueKey('member_list_add')));
    await tester.tap(find.byKey(const ValueKey('member_remove_dee')));
    await tester.pump();

    expect(events, ['add', 'remove dee']);
    expect(find.byKey(const ValueKey('member_remove_family')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('offers Message on every account but your own', (
    tester,
    size,
  ) async {
    final messaged = <String>[];
    await pumpAt(
      tester,
      QuarkMemberList(
        members: members,
        selfId: 'ada',
        expandedIds: const {'family'},
        onMessage: messaged.add,
      ),
      size: size,
    );

    Finder message(String id) => find.byKey(ValueKey('member_message_$id'));
    expect(message('ada'), findsNothing, reason: 'yourself');
    expect(message('family'), findsNothing, reason: 'a group');
    expect(find.byKey(const ValueKey('member_remove_dee')), findsNothing);
    await tester.tap(message('dee'));
    await tester.tap(message('bob'));
    expect(messaged, ['dee', 'bob']);
    expect(tester.takeException(), isNull);
  });

  // #2949: an anonymous channel names accounts by alias; a manager also
  // sees the username behind each and may rename the alias.
  testBothViewports('shows a manager the account behind each alias', (
    tester,
    size,
  ) async {
    const anonymous = [
      ChatMemberItem(
        id: '8',
        name: 'Fox',
        accountName: 'bob',
        permissions: {ChatPermission.readMessages},
      ),
      ChatMemberItem(
        id: 'group_3',
        name: 'mods',
        isGroup: true,
        permissions: {ChatPermission.readMessages},
        members: [ChatMemberItem(id: '9', name: 'Owl', accountName: 'cy')],
      ),
    ];
    final renamed = <String>[];
    await pumpAt(
      tester,
      QuarkMemberList(
        members: anonymous,
        permissions: ChatPermissionPreset.moderator.permissions,
        expandedIds: const {'group_3'},
        onEditAlias: renamed.add,
      ),
      size: size,
    );

    Finder alias(String id) => find.byKey(ValueKey('member_alias_$id'));
    expect(find.text('Fox'), findsOneWidget);
    expect(find.textContaining('bob'), findsOneWidget);
    expect(alias('group_3'), findsNothing, reason: 'a group has no alias');
    await tester.tap(alias('8'));
    await tester.tap(alias('9'));
    expect(renamed, ['8', '9']);
    expect(tester.takeException(), isNull);

    await pumpAt(
      tester,
      QuarkMemberList(
        members: anonymous,
        permissions: ChatPermissionPreset.member.permissions,
        expandedIds: const {'group_3'},
        selfId: '9',
        onEditAlias: renamed.add,
      ),
      size: size,
    );
    expect(alias('8'), findsNothing, reason: 'only a manager renames others');
    await tester.tap(alias('9'));
    expect(renamed, ['8', '9', '9'], reason: 'anyone renames themselves');
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a viewer no member-management buttons', (tester) async {
    await pumpAt(
      tester,
      QuarkMemberList(
        members: members,
        permissions: ChatPermissionPreset.viewer.permissions,
        onAddMembers: () {},
        onRemove: (_) {},
      ),
    );

    expect(find.byKey(const ValueKey('member_list_add')), findsNothing);
    expect(find.byKey(const ValueKey('member_remove_dee')), findsNothing);
  });

  testBothViewports('survives long names and many members', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkMemberList(
        members: [
          for (var i = 0; i < 200; i++)
            ChatMemberItem(
              id: '$i',
              name: 'n' * 300,
              isGroup: i.isEven,
              permissions: ChatPermissionPreset.member.permissions,
            ),
        ],
        permissions: ChatPermissionPreset.owner.permissions,
        onAddMembers: () {},
        onRemove: (_) {},
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
  });

  testBothViewports('meets the tap target guidelines', (tester, size) async {
    await pumpAt(
      tester,
      Padding(
        padding: const EdgeInsets.all(16),
        child: QuarkMemberList(
          members: members,
          permissions: ChatPermissionPreset.moderator.permissions,
          onAddMembers: () {},
          onRemove: (_) {},
        ),
      ),
      size: size,
    );

    for (final key in const ['member_list_add', 'member_remove_dee']) {
      final box = tester.getSize(find.byKey(ValueKey(key)));
      expect(box.shortestSide, greaterThanOrEqualTo(48), reason: key);
    }
    await expectTapTargetGuidelines(tester);
  });
}
