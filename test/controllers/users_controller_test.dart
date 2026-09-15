import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/users_controller.dart';
import 'package:quark/models/user_account.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Users page's state (#1662): the accounts, and promote and demote.
void main() {
  const ada = UserAccount(id: 1, username: 'ada', isAdmin: true);
  const bob = UserAccount(id: 2, username: 'bob');
  const cy = UserAccount(id: 3, username: 'cy', status: UserAccount.pending);

  late List<UserAccount> users;
  late List<String> calls;

  setUp(() {
    users = [ada, bob, cy];
    calls = [];
  });

  UsersController controller({
    Object? promoteError,
    Object? demoteError,
    Object? listError,
  }) => UsersController(
    selfUsername: 'ada',
    listUsers: () async {
      calls.add('list');
      if (listError != null) throw listError;
      return users;
    },
    promoteUser: (username) async {
      calls.add('promote $username');
      if (promoteError != null) throw promoteError;
    },
    demoteUser: (username) async {
      calls.add('demote $username');
      if (demoteError != null) throw demoteError;
    },
  );

  test('loads the accounts, leaving pending requests out', () async {
    final c = controller();
    var notified = 0;
    c.addListener(() => notified++);

    await c.load();

    expect(c.accounts, const [
      UserAccountItem(username: 'ada', isAdmin: true),
      UserAccountItem(username: 'bob'),
    ]);
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
    final c = UsersController(
      listUsers: () async {
        if (fail) throw const ApiException(500);
        return users;
      },
    );

    await c.load();
    expect(c.error, isA<ApiException>());
    expect(c.hasLoaded, isFalse);
    expect(c.isLoading, isFalse);

    fail = false;
    await c.load();
    expect(c.error, isNull);
    expect(c.accounts, hasLength(2));
  });

  test('a slow load cannot overwrite a newer one', () async {
    final slow = Completer<List<UserAccount>>();
    var first = true;
    final c = UsersController(
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

  test('promotes, then reloads', () async {
    final c = controller();

    final error = await c.promote('bob');

    expect(error, isNull);
    expect(calls, ['promote bob', 'list']);
    expect(c.busyUsernames, isEmpty);
  });

  test('demotes, then reloads', () async {
    final c = controller();

    final error = await c.demote('ada');

    expect(error, isNull);
    expect(calls, ['demote ada', 'list']);
  });

  test('hands back a refused action and does not reload', () async {
    final refusal = MessageException(Errors.lastAdmin);
    final c = controller(demoteError: refusal);

    final error = await c.demote('ada');

    expect(error, same(refusal));
    expect(calls, ['demote ada']);
    expect(c.busyUsernames, isEmpty);
  });

  test('marks the account busy while its action is in flight', () async {
    final gate = Completer<void>();
    final c = UsersController(
      listUsers: () async => users,
      promoteUser: (_) => gate.future,
    );

    final pending = c.promote('bob');
    expect(c.busyUsernames, {'bob'});

    // A second tap on the same account while the first is in flight is a
    // no-op, not a second request.
    expect(await c.promote('bob'), isNull);

    gate.complete();
    await pending;
    expect(c.busyUsernames, isEmpty);
  });

  test('a response landing after dispose does not notify', () async {
    final slow = Completer<List<UserAccount>>();
    final c = UsersController(listUsers: () => slow.future);

    final loading = c.load();
    c.dispose();
    slow.complete(users);

    await expectLater(loading, completes);
  });
}
