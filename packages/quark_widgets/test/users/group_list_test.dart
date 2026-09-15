import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The groups list on the Users page (#1910). The part worth guarding is that
/// the built-in `everyone` group offers nothing, and that each menu entry
/// reports the group it belongs to.
void main() {
  const ada = PrincipalItem(kind: PrincipalKind.user, id: 1, name: 'ada');
  const bob = PrincipalItem(kind: PrincipalKind.user, id: 2, name: 'bob');
  const groups = [
    GroupItem(id: 1, name: 'everyone', isBuiltin: true),
    GroupItem(id: 2, name: 'Family', members: [ada, bob]),
    GroupItem(id: 3, name: 'Book club', members: [ada]),
    GroupItem(id: 4, name: 'Chess'),
  ];

  Future<void> openMenu(WidgetTester tester, int id) async {
    await tester.tap(find.byKey(ValueKey('group_menu_$id')));
    await tester.pumpAndSettle();
  }

  testBothViewports('shows a spinner while loading and no rows', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const GroupList(groups: groups, isLoading: true),
      size: size,
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('group_row_1')), findsNothing);
    expect(find.text('No groups yet'), findsNothing);
  });

  testBothViewports('renders the error the caller handed it', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const GroupList(groups: groups, error: "Couldn't load groups."),
      size: size,
    );

    expect(find.text("Couldn't load groups."), findsOneWidget);
    expect(find.byKey(const ValueKey('group_row_1')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testBothViewports('shows the empty copy when there are no groups', (
    tester,
    size,
  ) async {
    await pumpAt(tester, const GroupList(groups: []), size: size);

    expect(find.text('No groups yet'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testBothViewports('renders one row per group with who is in it', (
    tester,
    size,
  ) async {
    await pumpAt(tester, const GroupList(groups: groups), size: size);

    for (final group in groups) {
      expect(find.byKey(ValueKey('group_row_${group.id}')), findsOneWidget);
    }
    expect(find.text('Every account'), findsOneWidget);
    expect(find.text('2 members'), findsOneWidget);
    expect(find.text('1 member'), findsOneWidget);
    expect(find.text('No members'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('the built-in group has no menu', (tester, size) async {
    await pumpAt(
      tester,
      GroupList(
        groups: groups,
        onMembers: (_) {},
        onRename: (_) {},
        onDelete: (_) {},
      ),
      size: size,
    );

    expect(find.byKey(const ValueKey('group_menu_1')), findsNothing);
    expect(find.byKey(const ValueKey('group_menu_2')), findsOneWidget);
  });

  testBothViewports('reports each action with the group it came from', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      GroupList(
        groups: groups,
        onMembers: (id) => events.add('members $id'),
        onRename: (id) => events.add('rename $id'),
        onDelete: (id) => events.add('delete $id'),
      ),
      size: size,
    );

    for (final (action, id) in [('members', 2), ('rename', 3), ('delete', 4)]) {
      await openMenu(tester, id);
      await tester.tap(find.byKey(ValueKey('group_action_${action}_$id')));
      await tester.pumpAndSettle();
    }

    expect(events, ['members 2', 'rename 3', 'delete 4']);
  });

  testBothViewports('the new-group button reports a tap', (tester, size) async {
    var created = 0;
    await pumpAt(
      tester,
      GroupList(groups: groups, onCreate: () => created++),
      size: size,
    );

    await tester.tap(find.byKey(const ValueKey('group_create')));
    await tester.pump();

    expect(created, 1);
  });

  testWidgets('the new-group button stays while loading and on an error', (
    tester,
  ) async {
    await pumpAt(
      tester,
      GroupList(groups: const [], isLoading: true, onCreate: () {}),
    );
    expect(find.byKey(const ValueKey('group_create')), findsOneWidget);

    await pumpAt(
      tester,
      GroupList(groups: const [], error: 'Nope.', onCreate: () {}),
    );
    expect(find.byKey(const ValueKey('group_create')), findsOneWidget);
  });

  testWidgets('no callbacks means no menus and no new-group button', (
    tester,
  ) async {
    await pumpAt(tester, const GroupList(groups: groups));

    expect(find.byType(PopupMenuButton<VoidCallback>), findsNothing);
    expect(find.byKey(const ValueKey('group_create')), findsNothing);
  });

  testWidgets('emits every documented action key', (tester) async {
    await pumpAt(
      tester,
      GroupList(
        groups: groups,
        onCreate: () {},
        onMembers: (_) {},
        onRename: (_) {},
        onDelete: (_) {},
      ),
    );

    expect(find.byKey(const ValueKey('group_create')), findsOneWidget);
    for (final group in groups.where((g) => !g.isBuiltin)) {
      await openMenu(tester, group.id);
      for (final action in ['members', 'rename', 'delete']) {
        expect(
          find.byKey(ValueKey('group_action_${action}_${group.id}')),
          findsOneWidget,
          reason: '$action is missing on ${group.name}',
        );
      }
      await tester.tap(
        find.byKey(ValueKey('group_action_members_${group.id}')),
      );
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a group with an action in flight shows progress', (
    tester,
  ) async {
    await pumpAt(
      tester,
      GroupList(groups: groups, busyIds: const {2}, onDelete: (_) {}),
    );

    expect(find.byKey(const ValueKey('group_menu_2')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('group_row_2')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
  });

  testWidgets('every menu button names itself', (tester) async {
    await pumpAt(tester, GroupList(groups: groups, onDelete: (_) {}));

    for (final button in tester.widgetList<PopupMenuButton<VoidCallback>>(
      find.byType(PopupMenuButton<VoidCallback>),
    )) {
      expect(button.tooltip, isNotNull, reason: 'an icon alone says nothing');
    }
  });

  testBothViewports('survives a long name and a long list', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      SingleChildScrollView(
        child: GroupList(
          groups: [
            for (var i = 0; i < 100; i++)
              GroupItem(id: i, name: 'group $i ${'x' * 80}', members: [ada]),
          ],
          onCreate: () {},
          onDelete: (_) {},
        ),
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
        const GroupList(groups: groups),
        brightness: brightness,
      );

      expect(tester.takeException(), isNull);
      final detail = tester.widget<Text>(find.text('Every account'));
      expect(detail.style?.color, tokens.mutedForeground);
    });

    testWidgets('$label: delete reads in the error color', (tester) async {
      await pumpAt(
        tester,
        GroupList(groups: groups, onDelete: (_) {}),
        brightness: brightness,
      );

      await openMenu(tester, 2);
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('group_action_delete_2')),
          matching: find.text('Delete'),
        ),
      );
      expect(text.style?.color, tokens.error);
    });

    testWidgets('$label: the error reads in the error color', (tester) async {
      await pumpAt(
        tester,
        const GroupList(groups: [], error: 'Nope.'),
        brightness: brightness,
      );

      expect(
        tester.widget<Text>(find.text('Nope.')).style?.color,
        tokens.error,
      );
    });
  }
}
