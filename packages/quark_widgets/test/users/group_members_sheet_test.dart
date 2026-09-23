import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// A group's members on the Users page (#1910). Worth guarding: removing
/// reports the member, the picker never offers someone already in the group,
/// and a member mid-change cannot be removed twice.
void main() {
  const ada = PrincipalItem(kind: PrincipalKind.user, id: 1, name: 'ada');
  const bob = PrincipalItem(kind: PrincipalKind.user, id: 2, name: 'bob');
  const cy = PrincipalItem(kind: PrincipalKind.user, id: 3, name: 'cy');
  const family = GroupItem(id: 7, name: 'Family', members: [ada, bob]);
  const candidates = [ada, bob, cy];

  testBothViewports('lists the members of the group', (tester, size) async {
    await pumpAt(
      tester,
      GroupMembersSheet(group: family, candidates: candidates, onAdd: (_) {}),
      size: size,
    );

    expect(find.text('Members of Family'), findsOneWidget);
    expect(find.byKey(const ValueKey('group_member_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('group_member_2')), findsOneWidget);
    expect(find.text('No members yet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('says so when the group has no members', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      GroupMembersSheet(
        group: const GroupItem(id: 7, name: 'Family'),
        candidates: candidates,
        onAdd: (_) {},
      ),
      size: size,
    );

    expect(find.text('No members yet'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('principal_option_user_1')),
      findsOneWidget,
    );
  });

  testBothViewports('reports the member to remove', (tester, size) async {
    final removed = <int>[];
    await pumpAt(
      tester,
      GroupMembersSheet(
        group: family,
        candidates: candidates,
        onRemove: removed.add,
      ),
      size: size,
    );

    await tester.tap(find.byKey(const ValueKey('group_member_remove_2')));
    await tester.pump();

    expect(removed, [2]);
  });

  testBothViewports('offers only accounts not already in the group', (
    tester,
    size,
  ) async {
    final added = <int>[];
    await pumpAt(
      tester,
      GroupMembersSheet(
        group: family,
        candidates: candidates,
        onAdd: added.add,
      ),
      size: size,
    );

    expect(find.byKey(const ValueKey('principal_option_user_1')), findsNothing);
    expect(find.byKey(const ValueKey('principal_option_user_2')), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('principal_option_user_3')),
    );
    await tester.tap(find.byKey(const ValueKey('principal_option_user_3')));
    await tester.pump();

    expect(added, [3]);
  });

  testWidgets('a member mid-change shows progress and no remove button', (
    tester,
  ) async {
    await pumpAt(
      tester,
      GroupMembersSheet(
        group: family,
        candidates: candidates,
        busyIds: const {1},
        onRemove: (_) {},
      ),
    );

    expect(find.byKey(const ValueKey('group_member_remove_1')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('group_member_1')),
        matching: find.byType(QuarkLoader),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no callbacks means no picker and no remove', (tester) async {
    await pumpAt(
      tester,
      const GroupMembersSheet(group: family, candidates: candidates),
    );

    expect(find.byKey(const ValueKey('principal_search')), findsNothing);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('group_member_remove_1')),
          )
          .onPressed,
      isNull,
    );
  });

  testBothViewports('shows the refusal the caller handed it', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const GroupMembersSheet(
        group: family,
        candidates: candidates,
        error: "That account can't join a group.",
      ),
      size: size,
    );

    expect(find.text("That account can't join a group."), findsOneWidget);
  });

  testWidgets('every remove button names itself', (tester) async {
    await pumpAt(
      tester,
      GroupMembersSheet(
        group: family,
        candidates: candidates,
        onRemove: (_) {},
      ),
    );

    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(button.tooltip, isNotNull, reason: 'an icon alone says nothing');
    }
  });

  testBothViewports('survives a long name and many members', (
    tester,
    size,
  ) async {
    final many = [
      for (var i = 0; i < 60; i++)
        PrincipalItem(
          kind: PrincipalKind.user,
          id: i,
          name: 'user$i${'x' * 80}',
        ),
    ];
    await pumpAt(
      tester,
      GroupMembersSheet(
        group: GroupItem(id: 7, name: 'Family ' * 20, members: many),
        candidates: [
          ...many,
          for (var i = 60; i < 120; i++)
            PrincipalItem(kind: PrincipalKind.user, id: i, name: 'user$i'),
        ],
        error: 'Nope. ' * 30,
        onAdd: (_) {},
        onRemove: (_) {},
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: colors come from the tokens', (tester) async {
      await pumpAt(
        tester,
        const GroupMembersSheet(
          group: GroupItem(id: 7, name: 'Family'),
          candidates: candidates,
          error: 'Nope.',
        ),
        brightness: brightness,
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.widget<Text>(find.text('Nope.')).style?.color,
        tokens.error,
      );
      expect(
        tester.widget<Text>(find.text('No members yet')).style?.color,
        tokens.mutedForeground,
      );
    });
  }
}
