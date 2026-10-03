import 'package:flutter/material.dart';
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

  testBothViewports('shows a spinner while loading and no rows', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkMemberList(members: members, isLoading: true),
      size: size,
    );

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.byKey(const ValueKey('member_row_ada')), findsNothing);
    expect(find.text('No members yet'), findsNothing);
  });

  testBothViewports('renders the error the caller handed it', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkMemberList(members: members, error: "Couldn't load members."),
      size: size,
    );

    expect(find.text("Couldn't load members."), findsOneWidget);
    expect(find.byKey(const ValueKey('member_row_ada')), findsNothing);
  });

  testBothViewports('shows the empty copy when there are no members', (
    tester,
    size,
  ) async {
    await pumpAt(tester, const QuarkMemberList(members: []), size: size);

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

  testBothViewports('lists a group\'s accounts when it is expanded', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkMemberList(members: members, expandedIds: const {'family'}),
      size: size,
    );

    expect(find.byKey(const ValueKey('member_row_family_bob')), findsOneWidget);
    expect(find.byKey(const ValueKey('member_row_family_cy')), findsOneWidget);
  });

  testBothViewports('reports the group that was tapped, not accounts', (
    tester,
    size,
  ) async {
    final toggled = <String>[];
    await pumpAt(
      tester,
      QuarkMemberList(
        members: members,
        expandedIds: const {'family'},
        onToggleExpanded: toggled.add,
      ),
      size: size,
    );

    await tester.tap(find.byKey(const ValueKey('member_row_ada')));
    await tester.tap(find.byKey(const ValueKey('member_row_family_bob')));
    await tester.tap(find.byKey(const ValueKey('member_row_family')));
    await tester.pump();

    expect(toggled, ['family']);
  });

  testBothViewports('hands account ids to the avatar builder', (
    tester,
    size,
  ) async {
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
      size: size,
    );

    expect(ids, ['ada', 'bob', 'cy', 'dee', 'eve']);
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

  testBothViewports('shows a viewer no member-management buttons', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkMemberList(
        members: members,
        permissions: ChatPermissionPreset.viewer.permissions,
        onAddMembers: () {},
        onRemove: (_) {},
      ),
      size: size,
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
