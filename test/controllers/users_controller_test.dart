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
      readAccessRequests: () async => accessRequests,
      setAccessRequests: (enabled) async {
        calls.add('access $enabled');
        if (setAccessError != null) throw setAccessError;
        return enabled;
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
