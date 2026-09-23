import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The share sheet (#1911). Worth guarding: inherited access never offers a
/// control, owner rows follow canGrantOwner, a locked row stays read-only for
/// a manager, and a sheet without canManage changes nothing.
void main() {
  const everyone = PrincipalItem(
    kind: PrincipalKind.group,
    id: 1,
    name: 'everyone',
    isBuiltin: true,
  );
  const family = PrincipalItem(
    kind: PrincipalKind.group,
    id: 2,
    name: 'Family',
  );
  const ada = PrincipalItem(kind: PrincipalKind.user, id: 1, name: 'ada');
  const bob = PrincipalItem(kind: PrincipalKind.user, id: 2, name: 'bob');
  const principals = [everyone, family, ada, bob];
  const grants = [
    GrantItem(principal: everyone, level: AccessLevel.read),
    GrantItem(principal: ada, level: AccessLevel.owner),
    GrantItem(principal: bob, level: AccessLevel.write),
    GrantItem(
      principal: family,
      level: AccessLevel.write,
      inheritedFrom: 'Shared',
    ),
    GrantItem(
      principal: bob,
      level: AccessLevel.owner,
      inheritedFrom: 'Shared',
    ),
  ];

  Widget sheet({
    List<GrantItem> grants = grants,
    bool canManage = true,
    bool canGrantOwner = true,
    Set<String> lockedKeys = const {},
    Set<String> busyKeys = const {},
    bool isLoading = false,
    String? error,
    List<String>? events,
  }) => ShareSheet(
    itemName: 'Recipes',
    grants: grants,
    principals: principals,
    canManage: canManage,
    canGrantOwner: canGrantOwner,
    lockedKeys: lockedKeys,
    busyKeys: busyKeys,
    isLoading: isLoading,
    error: error,
    onAdd: (p, level) => events?.add('add ${p.keySuffix} ${level.name}'),
    onSetLevel: (p, level) => events?.add('level ${p.keySuffix} ${level.name}'),
    onRevoke: (p) => events?.add('revoke ${p.keySuffix}'),
  );

  Finder key(String value) => find.byKey(ValueKey(value));

  Future<void> tapKey(WidgetTester tester, String value) async {
    await tester.ensureVisible(key(value));
    await tester.pumpAndSettle();
    await tester.tap(key(value));
    await tester.pumpAndSettle();
  }

  VoidCallback? revokeOf(WidgetTester tester, String suffix) =>
      tester.widget<IconButton>(key('share_revoke_$suffix')).onPressed;

  bool levelMenuEnabled(WidgetTester tester, String suffix) => tester
      .widget<PopupMenuButton<AccessLevel>>(key('share_level_$suffix'))
      .enabled;

  testBothViewports('shows a spinner while loading and nothing else', (
    tester,
    size,
  ) async {
    await pumpAt(tester, sheet(isLoading: true), size: size);

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(key('share_grant_user_1'), findsNothing);
    expect(key('share_add_submit'), findsNothing);
  });

  testBothViewports('a load that failed shows only its reason', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      sheet(
        grants: const [],
        canManage: false,
        error: 'Only the owner or an admin can change sharing.',
      ),
      size: size,
    );

    expect(
      find.text('Only the owner or an admin can change sharing.'),
      findsOneWidget,
    );
    expect(find.text('Who has access'), findsNothing);
    expect(key('principal_search'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testBothViewports(
    'lists access set on the item, then inherited access with its folder',
    (tester, size) async {
      await pumpAt(tester, sheet(), size: size);

      for (final suffix in ['group_1', 'user_1', 'user_2']) {
        expect(key('share_grant_$suffix'), findsOneWidget, reason: suffix);
      }
      expect(key('share_inherited_group_2'), findsOneWidget);
      expect(key('share_inherited_user_2'), findsOneWidget);
      expect(find.text('Can edit · From Shared'), findsOneWidget);
      expect(find.text('Owner · From Shared'), findsOneWidget);
      expect(find.text('Every account'), findsWidgets);
      expect(
        tester.getTopLeft(find.text('Who has access')).dy,
        lessThan(tester.getTopLeft(find.text('Inherited access')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inherited access offers no control at all', (tester) async {
    await pumpAt(tester, sheet());

    for (final suffix in ['group_2', 'user_2']) {
      expect(
        find.descendant(
          of: key('share_inherited_$suffix'),
          matching: find.byType(IconButton),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: key('share_inherited_$suffix'),
          matching: find.byType(PopupMenuButton<AccessLevel>),
        ),
        findsNothing,
      );
    }
    expect(key('share_revoke_group_2'), findsNothing);
    expect(key('share_level_group_2'), findsNothing);
  });

  testBothViewports('reports a level change and a removal with who for', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(tester, sheet(events: events), size: size);

    await tapKey(tester, 'share_level_user_2');
    await tester.tap(key('share_level_user_2_read'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'share_revoke_group_1');

    expect(events, ['level user_2 read', 'revoke group_1']);
  });

  testWidgets('owner is only on offer with canGrantOwner', (tester) async {
    await pumpAt(tester, sheet(canGrantOwner: false));

    expect(key('share_add_level_owner'), findsNothing);
    expect(levelMenuEnabled(tester, 'user_1'), isFalse);
    expect(revokeOf(tester, 'user_1'), isNull);
    await tapKey(tester, 'share_level_user_2');
    expect(key('share_level_user_2_write'), findsOneWidget);
    expect(key('share_level_user_2_owner'), findsNothing);
    await tester.tap(key('share_level_user_2_write'));
    await tester.pumpAndSettle();

    await pumpAt(tester, sheet());

    expect(key('share_add_level_owner'), findsOneWidget);
    expect(levelMenuEnabled(tester, 'user_1'), isTrue);
    await tapKey(tester, 'share_level_user_2');
    expect(key('share_level_user_2_owner'), findsOneWidget);
  });

  testWidgets('a locked row stays read-only for a manager', (tester) async {
    await pumpAt(tester, sheet(lockedKeys: const {'user_1'}));

    expect(levelMenuEnabled(tester, 'user_1'), isFalse);
    expect(revokeOf(tester, 'user_1'), isNull);
    expect(levelMenuEnabled(tester, 'user_2'), isTrue);
    expect(revokeOf(tester, 'user_2'), isNotNull);
  });

  testWidgets('without canManage the sheet changes nothing', (tester) async {
    await pumpAt(tester, sheet(canManage: false));

    expect(key('principal_search'), findsNothing);
    expect(key('share_add_submit'), findsNothing);
    for (final suffix in ['group_1', 'user_1', 'user_2']) {
      expect(levelMenuEnabled(tester, suffix), isFalse, reason: suffix);
      expect(revokeOf(tester, suffix), isNull, reason: suffix);
    }
  });

  testWidgets('a row with a change in flight shows progress', (tester) async {
    await pumpAt(tester, sheet(busyKeys: const {'user_2'}));

    expect(key('share_revoke_user_2'), findsNothing);
    expect(
      find.descendant(
        of: key('share_grant_user_2'),
        matching: find.byType(QuarkLoader),
      ),
      findsOneWidget,
    );
  });

  testBothViewports('shares with the picked group at the chosen level', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(tester, sheet(events: events), size: size);

    expect(
      tester.widget<FilledButton>(key('share_add_submit')).onPressed,
      isNull,
      reason: 'nothing picked yet',
    );
    await tapKey(tester, 'principal_option_group_2');
    await tapKey(tester, 'share_add_level_write');
    await tapKey(tester, 'share_add_submit');

    expect(events, ['add group_2 write']);
  });

  testWidgets('the share button waits while that share is out', (tester) async {
    final events = <String>[];
    await pumpAt(tester, sheet(events: events));
    await tapKey(tester, 'principal_option_user_2');

    await pumpAt(tester, sheet(events: events, busyKeys: const {'user_2'}));

    expect(
      tester.widget<FilledButton>(key('share_add_submit')).onPressed,
      isNull,
    );
    expect(
      find.descendant(
        of: key('share_add_submit'),
        matching: find.byType(QuarkLoader),
      ),
      findsOneWidget,
    );
  });

  testWidgets('says so when nothing is set on the item itself', (tester) async {
    await pumpAt(
      tester,
      sheet(
        grants: const [
          GrantItem(
            principal: family,
            level: AccessLevel.read,
            inheritedFrom: 'Shared',
          ),
        ],
      ),
    );

    expect(find.text('No one has access set on this item'), findsOneWidget);
    expect(key('share_inherited_group_2'), findsOneWidget);
  });

  testWidgets('every icon control names itself', (tester) async {
    await pumpAt(tester, sheet());

    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(button.tooltip, isNotNull, reason: 'an icon alone says nothing');
    }
    for (final menu in tester.widgetList<PopupMenuButton<AccessLevel>>(
      find.byType(PopupMenuButton<AccessLevel>),
    )) {
      expect(menu.tooltip, isNotNull);
    }
  });

  testBothViewports('survives long names and many grants', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      ShareSheet(
        itemName: 'A folder with a very long name ' * 5,
        grants: [
          for (var i = 0; i < 40; i++)
            GrantItem(
              principal: PrincipalItem(
                kind: i.isEven ? PrincipalKind.user : PrincipalKind.group,
                id: i,
                name: 'name $i ${'x' * 80}',
              ),
              level: AccessLevel.values[i % 3],
              inheritedFrom: i % 4 == 0 ? 'Folder ${'y' * 80}' : null,
            ),
        ],
        principals: principals,
        canManage: true,
        canGrantOwner: true,
        error: 'That did not work. ' * 10,
        onAdd: (_, _) {},
        onSetLevel: (_, _) {},
        onRevoke: (_) {},
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
      await pumpAt(tester, sheet(error: 'Nope.'), brightness: brightness);

      expect(tester.takeException(), isNull);
      expect(
        tester.widget<Text>(find.text('Nope.')).style?.color,
        tokens.error,
      );
      expect(
        tester.widget<Text>(find.text('Can edit · From Shared')).style?.color,
        tokens.mutedForeground,
      );
    });
  }
}
