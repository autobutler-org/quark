import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/controllers/chat_channel_share_target.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/widgets/sharing/show_share_sheet.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The share sheet host (#1911). Removing or demoting an owner can leave an
/// item that only admins manage, so it asks first, and sends nothing until
/// the admin confirms.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <http.Request>[];
  late int loadStatus;

  const bobOwner = {
    'userId': 2,
    'name': 'bob',
    'builtin': false,
    'level': 'owner',
    'from': 'Family',
  };
  const everyoneFromTop = {
    'groupId': 1,
    'name': 'everyone',
    'builtin': true,
    'level': 'read',
    'from': '',
  };

  Map<String, Object> access(List<Object> grants) => {
    'deviceSerial': 'ssd1',
    'relPath': 'Family',
    'canManage': true,
    'canGrantOwner': true,
    'grants': grants,
  };

  setUp(() {
    requests.clear();
    loadStatus = 200;
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/api/v0/access/principals') {
        return http.Response(
          jsonEncode({
            'users': [
              {'id': 2, 'username': 'bob'},
            ],
            'groups': [
              {'id': 1, 'name': 'everyone', 'builtin': true},
            ],
          }),
          200,
        );
      }
      if (request.method == 'GET' && loadStatus != 200) {
        return http.Response(
          jsonEncode({
            'error': 'only the owner or an admin can change sharing',
          }),
          loadStatus,
        );
      }
      final grants = switch (request.method) {
        'DELETE' => [everyoneFromTop],
        'PUT' => [
          {...bobOwner, 'level': 'write'},
          everyoneFromTop,
        ],
        _ => [bobOwner, everyoneFromTop],
      };
      return http.Response(jsonEncode(access(grants)), 200);
    });
  });

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  Future<void> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showShareSheet(
                context,
                deviceSerial: 'ssd1',
                relPath: 'Family',
                name: 'Family',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  Iterable<http.Request> changes() =>
      requests.where((r) => r.method == 'PUT' || r.method == 'DELETE');

  testWidgets('loads who has access to the item', (tester) async {
    await openSheet(tester);

    final load = requests.firstWhere((r) => r.url.path == '/api/v0/access');
    expect(load.url.queryParameters, {'serial': 'ssd1', 'relPath': 'Family'});
    expect(find.text('Share Family'), findsOneWidget);
    expect(find.byKey(const ValueKey('share_grant_user_2')), findsOneWidget);
    expect(find.text('Can view · From /'), findsOneWidget);
  });

  testWidgets('asks before removing an owner, and removes only on confirm', (
    tester,
  ) async {
    await openSheet(tester);

    await tapKey(tester, 'share_revoke_user_2');
    expect(find.text("Remove bob's access?"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('revoke_owner_cancel')));
    await tester.pumpAndSettle();
    expect(changes(), isEmpty);

    await tapKey(tester, 'share_revoke_user_2');
    await tester.tap(find.byKey(const ValueKey('revoke_owner_confirm')));
    await tester.pumpAndSettle();

    expect(jsonDecode(changes().single.body), {
      'deviceSerial': 'ssd1',
      'relPath': 'Family',
      'userId': 2,
    });
    expect(
      find.byKey(const ValueKey('share_grant_user_2')),
      findsNothing,
      reason: "the Quark's answer replaced the list",
    );
  });

  testWidgets('asks before giving an owner a lower level', (tester) async {
    await openSheet(tester);

    await tapKey(tester, 'share_level_user_2');
    await tester.tap(find.byKey(const ValueKey('share_level_user_2_write')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('demote_owner_confirm')), findsOneWidget);
    expect(changes(), isEmpty);

    await tester.tap(find.byKey(const ValueKey('demote_owner_confirm')));
    await tester.pumpAndSettle();

    expect(changes().single.method, 'PUT');
    expect(jsonDecode(changes().single.body)['level'], 'write');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('share_grant_user_2')),
        matching: find.text('Can edit'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('asks before the share form gives an owner a lower level', (
    tester,
  ) async {
    await openSheet(tester);

    Future<void> shareBobAsEditor() async {
      await tester.enterText(
        find.byKey(const ValueKey('principal_search')),
        'bob',
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'principal_option_user_2');
      await tapKey(tester, 'share_add_level_write');
      await tapKey(tester, 'share_add_submit');
    }

    await shareBobAsEditor();
    expect(find.text('Stop bob being an owner?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('demote_owner_cancel')));
    await tester.pumpAndSettle();
    expect(changes(), isEmpty);

    await shareBobAsEditor();
    await tester.tap(find.byKey(const ValueKey('demote_owner_confirm')));
    await tester.pumpAndSettle();

    expect(changes().single.method, 'PUT');
    expect(jsonDecode(changes().single.body)['level'], 'write');
  });

  testWidgets('a reader sees why they cannot manage sharing', (tester) async {
    loadStatus = 403;

    await openSheet(tester);

    expect(
      find.text('Only the owner or an admin can change sharing.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('principal_search')), findsNothing);
  });

  group('for a chat channel (#2422)', () {
    const member = {
      ChatPermission.readMessages,
      ChatPermission.sendMessages,
      ChatPermission.addReactions,
    };
    const everyoneRow = ChatMember(
      groupId: 1,
      name: 'everyone',
      permissions: member,
      builtin: true,
    );
    final owner = ChatPermission.values.toSet();
    late List<String> calls;
    late List<ChatMember> members;

    String ids(Set<ChatPermission>? permissions) => permissions == null
        ? 'none'
        : [
            for (final p in ChatPermission.values)
              if (permissions.contains(p)) p.id,
          ].join(',');

    Future<void> openChannel(
      WidgetTester tester,
      ChatChannel channel, {
      Size size = const Size(1280, 800),
    }) async {
      calls = [];
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final target = ChatChannelShareTarget(
        channel: channel,
        selfUserId: 7,
        listMembers: (_) async => members,
        setMember: (id, {userId, groupId, required permissions}) async {
          calls.add('set $id user=$userId ${ids(permissions)}');
          members = [
            for (final m in members)
              if (m.userId != userId || userId == null) m,
            ChatMember(userId: userId, name: 'bob', permissions: permissions),
          ];
          return (members: members, event: null);
        },
        removeMember: (id, {userId, groupId}) async {
          calls.add('remove $id user=$userId group=$groupId');
          members = [
            for (final m in members)
              if (m.groupId != groupId || m.userId != userId) m,
          ];
          return (members: members, event: null);
        },
        signMemberChange: (event, {userId, groupId, permissions}) async =>
            calls.add('sign user=$userId group=$groupId ${ids(permissions)}'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showShareSheetFor(
                  context,
                  target: target,
                  name: '#${channel.name}',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    for (final (label, size) in [
      ('narrow', const Size(360, 640)),
      ('wide', const Size(1280, 800)),
    ]) {
      testWidgets('adds a Moderator and removes a group ($label)', (
        tester,
      ) async {
        members = const [everyoneRow];
        await openChannel(
          tester,
          ChatChannel(id: 2, name: 'design', permissions: owner),
          size: size,
        );
        expect(find.text('Share #design'), findsOneWidget);
        expect(requests.where((r) => r.url.path == '/api/v0/access'), isEmpty);

        await tester.enterText(
          find.byKey(const ValueKey('principal_search')),
          'bob',
        );
        await tester.pumpAndSettle();
        await tapKey(tester, 'principal_option_user_2');
        await tapKey(tester, 'share_add_perms_preset_moderator');
        await tapKey(tester, 'share_add_submit');
        expect(
          find.byKey(const ValueKey('share_grant_user_2')),
          findsOneWidget,
        );

        // everyone reads, so removing it warns that the key rotates.
        await tapKey(tester, 'share_revoke_group_1');
        expect(find.textContaining("key will change"), findsOneWidget);
        await tapKey(tester, 'rotate_key_confirm');
        expect(calls, [
          'set 2 user=2 read_messages,send_messages,add_reactions,'
              'delete_messages,manage_reactions,manage_members',
          'sign user=2 group=null read_messages,send_messages,add_reactions,'
              'delete_messages,manage_reactions,manage_members',
          'remove 2 user=null group=1',
          'sign user=null group=1 none',
        ]);
        expect(find.byKey(const ValueKey('share_grant_group_1')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a custom set shows as Custom', (tester) async {
      members = const [
        ChatMember(
          userId: 2,
          name: 'bob',
          permissions: {ChatPermission.manageMembers},
        ),
      ];
      await openChannel(
        tester,
        ChatChannel(id: 2, name: 'design', permissions: owner),
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('share_grant_user_2')),
          matching: find.text('Custom'),
        ),
        findsWidgets,
      );
    });

    testWidgets('dropping read_messages warns first', (tester) async {
      members = const [ChatMember(userId: 2, name: 'bob', permissions: member)];
      await openChannel(
        tester,
        ChatChannel(id: 2, name: 'design', permissions: owner),
      );

      await tapKey(tester, 'share_perms_user_2_preset_custom');
      await tapKey(tester, 'share_perms_user_2_read_messages');
      // bob keeps nothing but would lose the key: clearing the last box
      // offers removal, with the rotation warning.
      expect(find.textContaining("key will change"), findsOneWidget);
      await tapKey(tester, 'rotate_key_cancel');
      expect(calls, isEmpty);

      // Adding a bit takes nothing away.
      await tapKey(tester, 'share_perms_user_2_manage_members');
      expect(find.textContaining("key will change"), findsNothing);
      expect(
        calls.first,
        'set 2 user=2 read_messages,send_messages,'
        'add_reactions,manage_members',
      );

      // Keeping manage_members without read_messages warns first.
      await tapKey(tester, 'share_perms_user_2_read_messages');
      expect(find.textContaining("key will change"), findsOneWidget);
      await tapKey(tester, 'rotate_key_confirm');
      expect(calls[2], 'set 2 user=2 manage_members');
    });

    testWidgets('a manage-only set changes without a key warning', (
      tester,
    ) async {
      // A manage-only set holds no key; another manage-only set takes
      // nothing away and asks nothing.
      members = const [
        ChatMember(
          userId: 2,
          name: 'bob',
          permissions: {ChatPermission.manageMembers},
        ),
      ];
      await openChannel(
        tester,
        ChatChannel(id: 2, name: 'design', permissions: owner),
      );
      await tapKey(tester, 'share_perms_user_2_manage_channel');
      expect(find.textContaining("key will change"), findsNothing);
      expect(calls, [
        'set 2 user=2 manage_channel,manage_members',
        'sign user=2 group=null manage_channel,manage_members',
      ]);
    });

    testWidgets('clearing every box removes the member', (tester) async {
      members = const [
        ChatMember(
          userId: 2,
          name: 'bob',
          permissions: {ChatPermission.manageMembers},
        ),
      ];
      await openChannel(
        tester,
        ChatChannel(id: 2, name: 'design', permissions: owner),
      );

      await tapKey(tester, 'share_perms_user_2_manage_members');
      expect(calls, [
        'remove 2 user=2 group=null',
        'sign user=2 group=null none',
      ]);
    });

    testWidgets('permissions the caller lacks are disabled', (tester) async {
      members = const [everyoneRow];
      await openChannel(
        tester,
        const ChatChannel(
          id: 2,
          name: 'design',
          permissions: {
            ChatPermission.readMessages,
            ChatPermission.sendMessages,
            ChatPermission.addReactions,
            ChatPermission.deleteMessages,
            ChatPermission.manageMembers,
          },
        ),
      );

      await tapKey(tester, 'share_add_perms_preset_custom');
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('share_add_perms_manage_channel')),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('share_add_perms_preset_owner')),
            )
            .onSelected,
        isNull,
      );
    });

    testWidgets("keeps general's everyone row", (tester) async {
      members = const [everyoneRow];
      await openChannel(
        tester,
        ChatChannel(
          id: 1,
          name: 'general',
          isDefault: true,
          permissions: owner,
        ),
      );

      expect(find.byKey(const ValueKey('share_grant_group_1')), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('share_revoke_group_1')),
            )
            .onPressed,
        isNull,
        reason: 'shown, but it cannot be removed',
      );
    });
  });
}
