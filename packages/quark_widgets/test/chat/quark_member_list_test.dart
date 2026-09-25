import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// A channel's member list (#2420): accounts with avatars, groups that expand
/// when the caller says so, and each state on its own.
void main() {
  const members = [
    ChatMemberItem(id: 'ada', name: 'Ada Lovelace', level: AccessLevel.owner),
    ChatMemberItem(
      id: 'family',
      name: 'Family',
      isGroup: true,
      level: AccessLevel.write,
      members: [
        ChatMemberItem(id: 'bob', name: 'Bob'),
        ChatMemberItem(id: 'cy', name: 'Cy'),
      ],
    ),
    ChatMemberItem(id: 'dee', name: 'Dee', level: AccessLevel.read),
  ];

  testBothViewports('shows a spinner while loading and no rows', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const QuarkMemberList(members: members, isLoading: true),
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
      const QuarkMemberList(members: members, error: "Couldn't load members."),
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

  testBothViewports('renders every member with its level, groups collapsed', (
    tester,
    size,
  ) async {
    await pumpAt(tester, const QuarkMemberList(members: members), size: size);

    for (final member in members) {
      expect(find.byKey(ValueKey('member_row_${member.id}')), findsOneWidget);
    }
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Can edit'), findsOneWidget);
    expect(find.text('Can view'), findsOneWidget);
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
      const QuarkMemberList(members: members, expandedIds: {'family'}),
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

    expect(ids, ['ada', 'bob', 'cy', 'dee']);
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
              level: AccessLevel.write,
            ),
        ],
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
  });
}
