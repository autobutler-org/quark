import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The accounts list on the Users page (#1662). The part worth guarding is
/// which actions each row offers: none on your own row, promote only for an
/// active non-admin, demote only for an admin.
void main() {
  const users = [
    UserAccountItem(username: 'ada', isAdmin: true),
    UserAccountItem(username: 'bob'),
    UserAccountItem(username: 'cy', status: UserAccountStatus.disabled),
  ];

  /// The list in a scroll view, the way a page hosts it.
  Widget scrolling(Widget list) => SingleChildScrollView(child: list);

  Future<void> openMenu(WidgetTester tester, String username) async {
    await tester.tap(find.byKey(ValueKey('user_menu_$username')));
    await tester.pumpAndSettle();
  }

  testBothViewports('shows a spinner while loading and no rows', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const UserList(users: users, isLoading: true),
      size: size,
    );

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.byKey(const ValueKey('user_row_ada')), findsNothing);
    expect(find.text('No accounts yet'), findsNothing);
  });

  testBothViewports('renders the error the caller handed it', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const UserList(users: users, error: "Couldn't load the accounts."),
      size: size,
    );

    expect(find.text("Couldn't load the accounts."), findsOneWidget);
    expect(find.byKey(const ValueKey('user_row_ada')), findsNothing);
    expect(find.byType(QuarkLoader), findsNothing);
  });

  testBothViewports('shows the empty copy when there are no accounts', (
    tester,
    size,
  ) async {
    await pumpAt(tester, const UserList(users: []), size: size);

    expect(find.text('No accounts yet'), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
  });

  testBothViewports('renders one row per account with what it is', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const UserList(users: users, selfUsername: 'ada'),
      size: size,
    );

    for (final user in users) {
      expect(find.byKey(ValueKey('user_row_${user.username}')), findsOneWidget);
    }
    expect(find.text('You · Admin'), findsOneWidget);
    expect(find.text('Turned off'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('offers promote for an active non-admin', (
    tester,
    size,
  ) async {
    final promoted = <String>[];
    await pumpAt(
      tester,
      UserList(
        users: users,
        onPromote: promoted.add,
        onDemote: (_) => fail('demote offered to a non-admin'),
      ),
      size: size,
    );

    await openMenu(tester, 'bob');
    expect(find.byKey(const ValueKey('user_action_demote_bob')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('user_action_promote_bob')));
    await tester.pumpAndSettle();

    expect(promoted, ['bob']);
  });

  testBothViewports('offers demote for an admin', (tester, size) async {
    final demoted = <String>[];
    await pumpAt(
      tester,
      UserList(users: users, onPromote: (_) {}, onDemote: demoted.add),
      size: size,
    );

    await openMenu(tester, 'ada');
    expect(find.byKey(const ValueKey('user_action_promote_ada')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('user_action_demote_ada')));
    await tester.pumpAndSettle();

    expect(demoted, ['ada']);
  });

  testBothViewports('offers nothing on your own row', (tester, size) async {
    await pumpAt(
      tester,
      UserList(
        users: users,
        selfUsername: 'ada',
        onPromote: (_) {},
        onDemote: (_) {},
      ),
      size: size,
    );

    expect(find.byKey(const ValueKey('user_menu_ada')), findsNothing);
    expect(find.byKey(const ValueKey('user_menu_bob')), findsOneWidget);
  });

  testWidgets('a disabled account cannot be promoted, so it has no menu', (
    tester,
  ) async {
    await pumpAt(tester, UserList(users: users, onPromote: (_) {}));

    expect(find.byKey(const ValueKey('user_menu_cy')), findsNothing);
  });

  testWidgets('no callbacks means no menus', (tester) async {
    await pumpAt(tester, const UserList(users: users));

    expect(find.byType(PopupMenuButton<VoidCallback>), findsNothing);
  });

  testBothViewports('turns off an active account and on a turned-off one', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      UserList(
        users: users,
        onDisable: (u) => events.add('disable $u'),
        onEnable: (u) => events.add('enable $u'),
      ),
      size: size,
    );

    await openMenu(tester, 'bob');
    expect(find.byKey(const ValueKey('user_action_enable_bob')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('user_action_disable_bob')));
    await tester.pumpAndSettle();

    await openMenu(tester, 'cy');
    expect(find.byKey(const ValueKey('user_action_disable_cy')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('user_action_enable_cy')));
    await tester.pumpAndSettle();

    expect(events, ['disable bob', 'enable cy']);
  });

  testBothViewports('offers delete on every account but your own', (
    tester,
    size,
  ) async {
    final deleted = <String>[];
    await pumpAt(
      tester,
      UserList(users: users, selfUsername: 'ada', onDelete: deleted.add),
      size: size,
    );

    expect(find.byKey(const ValueKey('user_menu_ada')), findsNothing);
    for (final name in ['bob', 'cy']) {
      await openMenu(tester, name);
      await tester.tap(find.byKey(ValueKey('user_action_delete_$name')));
      await tester.pumpAndSettle();
    }

    expect(deleted, ['bob', 'cy']);
  });

  testWidgets('emits every documented action key for another admin', (
    tester,
  ) async {
    await pumpAt(
      tester,
      UserList(
        users: const [UserAccountItem(username: 'grace', isAdmin: true)],
        onPromote: (_) {},
        onDemote: (_) {},
        onDisable: (_) {},
        onEnable: (_) {},
        onDelete: (_) {},
      ),
    );

    await openMenu(tester, 'grace');
    for (final action in ['demote', 'disable', 'delete']) {
      expect(
        find.byKey(ValueKey('user_action_${action}_grace')),
        findsOneWidget,
        reason: '$action is missing',
      );
    }
    // An admin is not promoted again, and an active account is not turned on.
    expect(
      find.byKey(const ValueKey('user_action_promote_grace')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('user_action_enable_grace')),
      findsNothing,
    );
  });

  testWidgets('an account with an action in flight shows progress', (
    tester,
  ) async {
    await pumpAt(
      tester,
      UserList(
        users: users,
        busyUsernames: const {'bob'},
        onPromote: (_) {},
        onDemote: (_) {},
      ),
    );

    expect(find.byKey(const ValueKey('user_menu_bob')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('user_row_bob')),
        matching: find.byType(QuarkLoader),
      ),
      findsOneWidget,
    );
  });

  testWidgets('every menu button names itself', (tester) async {
    await pumpAt(
      tester,
      UserList(users: users, onPromote: (_) {}, onDemote: (_) {}),
    );

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
      scrolling(
        UserList(
          users: [
            for (var i = 0; i < 100; i++)
              UserAccountItem(username: 'user$i${'x' * 60}', isAdmin: i.isOdd),
          ],
          onPromote: (_) {},
          onDemote: (_) {},
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
        const UserList(users: users),
        brightness: brightness,
      );

      expect(tester.takeException(), isNull);
      final detail = tester.widget<Text>(find.text('Admin'));
      expect(detail.style?.color, tokens.mutedForeground);
    });

    testWidgets('$label: delete reads in the error color', (tester) async {
      await pumpAt(
        tester,
        UserList(users: users, onDelete: (_) {}),
        brightness: brightness,
      );

      await openMenu(tester, 'bob');
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('user_action_delete_bob')),
          matching: find.text('Delete'),
        ),
      );
      expect(text.style?.color, tokens.error);
    });

    testWidgets('$label: the error reads in the error color', (tester) async {
      await pumpAt(
        tester,
        const UserList(users: [], error: 'Nope.'),
        brightness: brightness,
      );

      expect(
        tester.widget<Text>(find.text('Nope.')).style?.color,
        tokens.error,
      );
    });
  }
}
