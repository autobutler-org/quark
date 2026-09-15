import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/groups_controller.dart';
import 'package:quark/models/group.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Groups tab's state (#1910): the groups, creating and renaming through
/// a dialog, deleting, and members.
void main() {
  const everyone = Group(id: 1, name: 'everyone', builtin: true);
  const family = Group(
    id: 2,
    name: 'Family',
    members: [GroupMember(id: 5, username: 'bob')],
  );

  late List<Group> groups;
  late List<String> calls;
  Object? listError;
  Object? actionError;

  setUp(() {
    groups = [everyone, family];
    calls = [];
    listError = null;
    actionError = null;
  });

  GroupsController controller({
    Future<List<Group>> Function()? listGroups,
    Future<void> Function(int id)? deleteGroup,
    Future<void> Function(String name)? createGroup,
  }) {
    Future<void> action(String call) async {
      calls.add(call);
      if (actionError != null) throw actionError!;
    }

    return GroupsController(
      listGroups:
          listGroups ??
          () async {
            calls.add('list');
            if (listError != null) throw listError!;
            return groups;
          },
      createGroup: createGroup ?? (name) => action('create $name'),
      renameGroup: (id, name) => action('rename $id $name'),
      deleteGroup: deleteGroup ?? (id) => action('delete $id'),
      addMember: (groupId, userId) => action('add $userId to $groupId'),
      removeMember: (groupId, userId) => action('remove $userId from $groupId'),
    );
  }

  test('loads the groups as the package shows them', () async {
    final c = controller();
    var notified = 0;
    c.addListener(() => notified++);

    await c.load();

    expect(c.hasLoaded, isTrue);
    expect(c.isLoading, isFalse);
    expect(c.error, isNull);
    expect(c.groups, const [
      GroupItem(id: 1, name: 'everyone', isBuiltin: true),
      GroupItem(
        id: 2,
        name: 'Family',
        members: [PrincipalItem(kind: PrincipalKind.user, id: 5, name: 'bob')],
      ),
    ]);
    expect(c.group(2)?.name, 'Family');
    expect(c.group(9), isNull);
    expect(notified, 2, reason: 'once to start, once to finish');
  });

  test('a failed reload keeps the last groups and says why', () async {
    final c = controller();
    await c.load();
    listError = const ApiException(500);

    await c.load();

    expect(c.error, isA<ApiException>());
    expect(c.hasLoaded, isTrue);
    expect(c.groups, hasLength(2));
  });

  test('a slow load cannot overwrite a newer one', () async {
    final slow = Completer<List<Group>>();
    var first = true;
    final c = controller(
      listGroups: () {
        if (first) {
          first = false;
          return slow.future;
        }
        return Future.value(const [everyone]);
      },
    );

    final stale = c.load();
    await c.load();
    slow.complete([everyone, family]);
    await stale;

    expect(c.groups.map((g) => g.id), [1]);
  });

  test('create saves the name and lists the groups again', () async {
    final c = controller();

    final created = await c.create('Book club');

    expect(created, isTrue);
    expect(calls, ['create Book club', 'list']);
    expect(c.saveError, isNull);
    expect(c.isSaving, isFalse);
  });

  test('a refused create keeps the reason for the open dialog', () async {
    final c = controller();
    actionError = const MessageException(
      'a group with that name already exists',
    );

    final created = await c.create('family');

    expect(created, isFalse);
    expect(calls, ['create family'], reason: 'nothing to reload');
    expect(
      Errors.message(c.saveError, 'create the group'),
      'A group with that name already exists.',
    );

    var notified = 0;
    c.addListener(() => notified++);
    c.clearSaveError();
    expect(c.saveError, isNull);
    expect(notified, 1);
  });

  test('a second save while one is out is ignored', () async {
    final pending = Completer<void>();
    final c = controller(
      createGroup: (name) {
        calls.add('create $name');
        return pending.future;
      },
    );

    final first = c.create('Family');
    expect(c.isSaving, isTrue);
    expect(await c.create('Kin'), isFalse);
    pending.complete();
    await first;

    expect(calls, ['create Family', 'list']);
  });

  test(
    'rename lists the groups again rather than reading the answer',
    () async {
      final c = controller();

      expect(await c.rename(2, 'Kin'), isTrue);

      expect(calls, ['rename 2 Kin', 'list']);
    },
  );

  test('delete marks the group busy until the list is back', () async {
    final pending = Completer<void>();
    final c = controller(
      deleteGroup: (id) {
        calls.add('delete $id');
        return pending.future;
      },
    );

    final deleting = c.delete(2);
    expect(c.busyGroupIds, {2});
    expect(await c.delete(2), isNull, reason: 'a second delete is ignored');
    pending.complete();

    expect(await deleting, isNull);
    expect(c.busyGroupIds, isEmpty);
    expect(calls, ['delete 2', 'list']);
  });

  test('a refused delete hands back the failure', () async {
    final c = controller();
    actionError = const ApiException(404);

    final error = await c.delete(2);

    expect(error, isA<ApiException>());
    expect(c.busyGroupIds, isEmpty);
    expect(calls, ['delete 2']);
  });

  test('members are added and removed one account at a time', () async {
    final c = controller();

    expect(await c.addMember(2, 7), isNull);
    expect(await c.removeMember(2, 5), isNull);

    expect(calls, ['add 7 to 2', 'list', 'remove 5 from 2', 'list']);
    expect(c.busyMemberIds, isEmpty);
  });

  test('a refused member change hands back the failure', () async {
    final c = controller();
    actionError = const MessageException(Errors.cannotJoinGroup);

    final error = await c.addMember(2, 7);

    expect(Errors.message(error, 'add the member'), Errors.cannotJoinGroup);
    expect(c.busyMemberIds, isEmpty);
  });

  test('an answer after dispose changes nothing', () async {
    final pending = Completer<List<Group>>();
    final c = controller(listGroups: () => pending.future);

    final loading = c.load();
    c.dispose();
    pending.complete(groups);
    await loading;

    expect(c.groups, isEmpty);
  });
}
