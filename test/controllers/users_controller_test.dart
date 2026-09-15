import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/users_controller.dart';
import 'package:quark/models/user_account.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Users page's state: the accounts, promote and demote (#1662), and
/// requests with the access-requests setting (#1908).
void main() {
  const ada = UserAccount(id: 1, username: 'ada', isAdmin: true);
  const bob = UserAccount(id: 2, username: 'bob');
  const cy = UserAccount(id: 3, username: 'cy', status: UserAccount.pending);

  late List<UserAccount> users;
  late List<String> calls;
  late bool accessRequests;

  setUp(() {
    users = [ada, bob, cy];
    calls = [];
    accessRequests = true;
  });

  UsersController controller({
    Object? actionError,
    Object? listError,
    Object? setAccessError,
    Object? createError,
    Future<List<UserAccount>> Function()? listUsers,
    Future<void> Function(String)? promoteUser,
  }) {
    Future<void> action(String name, String username) async {
      calls.add('$name $username');
      if (actionError != null) throw actionError;
    }

    return UsersController(
      selfUsername: 'ada',
      listUsers:
          listUsers ??
          () async {
            calls.add('list');
            if (listError != null) throw listError;
            return users;
          },
      promoteUser: promoteUser ?? (u) => action('promote', u),
      demoteUser: (u) => action('demote', u),
      approveRequest: (u) => action('approve', u),
      denyRequest: (u) => action('deny', u),
      disableUser: (u) => action('disable', u),
      enableUser: (u) => action('enable', u),
      deleteUser: (u) async {
        await action('delete', u);
        return 2;
      },
      readAccessRequests: () async => accessRequests,
      setAccessRequests: (enabled) async {
        calls.add('access $enabled');
        if (setAccessError != null) throw setAccessError;
        return enabled;
      },
      createUser:
          ({
            required username,
            required password,
            required createFolder,
          }) async {
            calls.add('create $username folder=$createFolder');
            if (createError != null) throw createError;
            return UserAccount(id: 9, username: username);
          },
    );
  }

  test('loads the accounts and the requests apart', () async {
    final c = controller();
    var notified = 0;
    c.addListener(() => notified++);

    await c.load();

    expect(c.accounts, const [
      UserAccountItem(username: 'ada', isAdmin: true),
      UserAccountItem(username: 'bob'),
    ]);
    expect(c.pending, const [
      UserAccountItem(username: 'cy', status: UserAccountStatus.pending),
    ]);
    expect(c.accessRequestsEnabled, isTrue);
    expect(c.hasLoaded, isTrue);
    expect(c.isLoading, isFalse);
    expect(c.error, isNull);
    // Once as the load starts, once when it lands.
    expect(notified, 2);
  });

  test('maps a disabled account to its status', () {
    expect(
      UsersController.itemFor(
        const UserAccount(id: 4, username: 'dee', status: UserAccount.disabled),
      ).status,
      UserAccountStatus.disabled,
    );
  });

  test('offers only accounts that can sign in as group members', () async {
    users = [
      ...users,
      const UserAccount(id: 4, username: 'dee', status: UserAccount.disabled),
    ];
    final c = controller();

    await c.load();

    // cy is pending and dee is turned off; the Quark refuses both (#1910).
    expect(c.activeAccounts, const [
      PrincipalItem(kind: PrincipalKind.user, id: 1, name: 'ada'),
      PrincipalItem(kind: PrincipalKind.user, id: 2, name: 'bob'),
    ]);
  });

  test('keeps the failure raw, and a good load clears it', () async {
    var fail = true;
    final c = controller(
      listUsers: () async {
        if (fail) throw const ApiException(500);
        return users;
      },
    );

    await c.load();
    expect(c.error, isA<ApiException>());
    expect(c.hasLoaded, isFalse);
    expect(c.accessRequestsEnabled, isNull);
    expect(c.isLoading, isFalse);

    fail = false;
    await c.load();
    expect(c.error, isNull);
    expect(c.accounts, hasLength(2));
  });

  test('a slow load cannot overwrite a newer one', () async {
    final slow = Completer<List<UserAccount>>();
    var first = true;
    final c = controller(
      listUsers: () {
        if (first) {
          first = false;
          return slow.future;
        }
        return Future.value(const [bob]);
      },
    );

    final stale = c.load();
    await c.load();
    slow.complete(const [ada, bob]);
    await stale;

    expect(c.accounts, const [UserAccountItem(username: 'bob')]);
    expect(c.isLoading, isFalse);
  });

  for (final (name, call, run) in [
    ('promotes', 'promote', (UsersController c) => c.promote('bob')),
    ('demotes', 'demote', (UsersController c) => c.demote('bob')),
    ('approves', 'approve', (UsersController c) => c.approve('bob')),
    ('denies', 'deny', (UsersController c) => c.deny('bob')),
    ('turns off', 'disable', (UsersController c) => c.disable('bob')),
    ('turns on', 'enable', (UsersController c) => c.enable('bob')),
    ('deletes', 'delete', (UsersController c) => c.delete('bob')),
  ]) {
    test('$name, then reloads', () async {
      final c = controller();

      final error = await run(c);

      expect(error, isNull);
      expect(calls, ['$call bob', 'list']);
      expect(c.busyUsernames, isEmpty);
    });
  }

  test('hands back a refused action and does not reload', () async {
    const refusal = MessageException(Errors.lastAdmin);
    final c = controller(actionError: refusal);

    final error = await c.demote('ada');

    expect(error, same(refusal));
    expect(calls, ['demote ada']);
    expect(c.busyUsernames, isEmpty);
  });

  test('marks the account busy while its action is in flight', () async {
    final gate = Completer<void>();
    final c = controller(promoteUser: (_) => gate.future);

    final pending = c.promote('bob');
    expect(c.busyUsernames, {'bob'});

    // A second tap on the same account while the first is in flight is a
    // no-op, not a second request.
    expect(await c.promote('bob'), isNull);

    gate.complete();
    await pending;
    expect(c.busyUsernames, isEmpty);
  });

  test('creates the account, then reloads', () async {
    final c = controller();

    final created = await c.create(
      const CreateUserInput(username: 'dee', password: 'hunter2hunter2'),
    );

    expect(created, isTrue);
    expect(calls, ['create dee folder=true', 'list']);
    expect(c.createError, isNull);
    expect(c.isCreating, isFalse);
  });

  test(
    'keeps a refused create for the open dialog, reloading nothing',
    () async {
      const refusal = MessageException('that username is taken');
      final c = controller(createError: refusal);

      final created = await c.create(
        const CreateUserInput(
          username: 'bob',
          password: 'hunter2hunter2',
          createFolder: false,
        ),
      );

      expect(created, isFalse);
      expect(c.createError, same(refusal));
      expect(calls, ['create bob folder=false']);

      c.clearCreateError();
      expect(c.createError, isNull);
    },
  );

  test('a second create while one is in flight sends nothing', () async {
    final gate = Completer<UserAccount>();
    var creates = 0;
    final c = UsersController(
      listUsers: () async => users,
      readAccessRequests: () async => true,
      createUser:
          ({required username, required password, required createFolder}) {
            creates++;
            return gate.future;
          },
    );
    const input = CreateUserInput(username: 'dee', password: 'hunter2hunter2');

    final first = c.create(input);
    expect(c.isCreating, isTrue);
    expect(await c.create(input), isFalse);
    gate.complete(const UserAccount(id: 9, username: 'dee'));
    await first;

    expect(creates, 1);
  });

  test('saves the access-requests setting the Quark returns', () async {
    final c = controller();
    await c.load();

    final error = await c.setAccessRequestsEnabled(false);

    expect(error, isNull);
    expect(c.accessRequestsEnabled, isFalse);
    expect(c.isSavingAccessRequests, isFalse);
    expect(calls.last, 'access false');
  });

  test('a refused setting change leaves the setting as it was', () async {
    final c = controller(setAccessError: const ApiException(500));
    await c.load();

    final error = await c.setAccessRequestsEnabled(false);

    expect(error, isA<ApiException>());
    expect(c.accessRequestsEnabled, isTrue);
    expect(c.isSavingAccessRequests, isFalse);
  });

  test('a response landing after dispose does not notify', () async {
    final slow = Completer<List<UserAccount>>();
    final c = controller(listUsers: () => slow.future);

    final loading = c.load();
    c.dispose();
    slow.complete(users);

    await expectLater(loading, completes);
  });
}
