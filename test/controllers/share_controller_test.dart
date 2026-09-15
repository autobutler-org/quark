import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/share_controller.dart';
import 'package:quark/models/path_grant.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The share sheet's state (#1911): access set on the item and inherited,
/// your own ownership locked, and every change answered with the whole list.
void main() {
  const adaOwner = PathGrant(
    userId: 1,
    name: 'ada',
    level: 'owner',
    from: 'Photos/Family',
  );
  const bobWriter = PathGrant(
    userId: 2,
    name: 'bob',
    level: 'write',
    from: 'Photos/Family',
  );
  const everyoneFromTop = PathGrant(
    groupId: 1,
    name: 'everyone',
    builtin: true,
    level: 'read',
    from: '',
  );
  const bobFromPhotos = PathGrant(
    userId: 2,
    name: 'bob',
    level: 'owner',
    from: 'Photos',
  );

  const ada = PrincipalItem(kind: PrincipalKind.user, id: 1, name: 'ada');
  const bob = PrincipalItem(kind: PrincipalKind.user, id: 2, name: 'bob');
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

  PathAccess access(List<PathGrant> grants, {bool canManage = true}) =>
      PathAccess(
        deviceSerial: 'ssd1',
        relPath: 'Photos/Family',
        canManage: canManage,
        canGrantOwner: canManage,
        grants: grants,
      );

  const principals = SharePrincipals(
    users: [(id: 1, username: 'ada'), (id: 2, username: 'bob')],
    groups: [
      (id: 1, name: 'everyone', builtin: true),
      (id: 2, name: 'Family', builtin: false),
    ],
  );

  late List<String> calls;
  setUp(() => calls = []);

  ShareController controller({
    String? selfUsername = 'ada',
    bool isAdmin = false,
    List<PathGrant> grants = const [
      adaOwner,
      bobWriter,
      everyoneFromTop,
      bobFromPhotos,
    ],
    Future<PathAccess> Function()? load,
    Future<PathAccess> Function()? change,
  }) => ShareController(
    deviceSerial: 'ssd1',
    // Not the Quark's spelling, which is what grants are compared with.
    relPath: 'Photos/Family/',
    selfUsername: selfUsername,
    isAdmin: isAdmin,
    loadAccess: ({required deviceSerial, required relPath}) {
      calls.add('load $deviceSerial $relPath');
      return load?.call() ?? Future.value(access(grants));
    },
    loadPrincipals: () async => principals,
    grantAccess:
        ({
          required deviceSerial,
          required relPath,
          userId,
          groupId,
          required level,
        }) {
          calls.add('grant user=$userId group=$groupId $level');
          return change?.call() ?? Future.value(access(const [adaOwner]));
        },
    revokeAccess: ({required deviceSerial, required relPath, userId, groupId}) {
      calls.add('revoke user=$userId group=$groupId');
      return change?.call() ?? Future.value(access(const [adaOwner]));
    },
  );

  test('loads the access, and who the item can be shared with', () async {
    final c = controller();
    var notified = 0;
    c.addListener(() => notified++);

    await c.load();

    expect(calls, ['load ssd1 Photos/Family/']);
    expect(c.hasLoaded, isTrue);
    expect(c.error, isNull);
    expect(c.canManage, isTrue);
    expect(c.canGrantOwner, isTrue);
    expect(c.grants, const [
      GrantItem(principal: ada, level: AccessLevel.owner),
      GrantItem(principal: bob, level: AccessLevel.write),
      GrantItem(
        principal: everyone,
        level: AccessLevel.read,
        inheritedFrom: '/',
      ),
      GrantItem(
        principal: bob,
        level: AccessLevel.owner,
        inheritedFrom: 'Photos',
      ),
    ]);
    // Groups first, everyone first among them.
    expect(c.principals, const [everyone, family, ada, bob]);
    expect(notified, 2, reason: 'once to start, once to finish');
  });

  test('names the folder inherited access comes from', () {
    expect(ShareController.folderName('Photos/Family'), 'Family');
    expect(ShareController.folderName('/Photos/Family/'), 'Family');
    expect(ShareController.folderName(''), '/');
    expect(ShareController.levelFor('write'), AccessLevel.write);
    expect(ShareController.levelFor('mystery'), AccessLevel.read);
  });

  test('your own ownership set on the item is locked', () async {
    final c = controller();
    await c.load();

    expect(c.lockedKeys, {'user_1'});
  });

  test('an admin locks nothing', () async {
    final c = controller(isAdmin: true);
    await c.load();

    expect(c.lockedKeys, isEmpty);
  });

  test(
    'ownership that is only inherited, or not ownership, is not locked',
    () async {
      final c = controller(selfUsername: 'bob');
      await c.load();

      // bob writes here and owns only through Photos.
      expect(c.lockedKeys, isEmpty);
    },
  );

  test('a refused load keeps the reason and shows nothing else', () async {
    final c = controller(
      load: () async => throw const MessageException(
        'only the owner or an admin can change sharing',
      ),
    );

    await c.load();

    expect(c.hasLoaded, isFalse);
    expect(c.canManage, isFalse);
    expect(c.grants, isEmpty);
    expect(
      Errors.message(c.error, 'load sharing'),
      'Only the owner or an admin can change sharing.',
    );
  });

  test(
    'sharing names the account or the group, and takes the answer',
    () async {
      final c = controller();
      await c.load();

      expect(await c.share(family, AccessLevel.write), isNull);
      expect(await c.share(bob, AccessLevel.read), isNull);

      expect(calls.skip(1), [
        'grant user=null group=2 write',
        'grant user=2 group=null read',
      ]);
      expect(c.grants, const [
        GrantItem(principal: ada, level: AccessLevel.owner),
      ]);
    },
  );

  test('removing takes the answer as the new state', () async {
    final c = controller();
    await c.load();

    expect(await c.revoke(bob), isNull);

    expect(calls.last, 'revoke user=2 group=null');
    expect(c.grants, hasLength(1));
  });

  test('a refused change hands back the failure and keeps the list', () async {
    final c = controller(
      change: () async => throw const MessageException(
        'that access comes from a parent folder; change it there',
      ),
    );
    await c.load();

    final error = await c.revoke(everyone);

    expect(
      Errors.message(error, 'remove access'),
      'That access comes from a parent folder; change it there.',
    );
    expect(c.grants, hasLength(4));
    expect(c.busyKeys, isEmpty);
  });

  test('marks the principal busy while its change is out', () async {
    final pending = Completer<PathAccess>();
    final c = controller(change: () => pending.future);
    await c.load();

    final sharing = c.share(bob, AccessLevel.owner);
    expect(c.busyKeys, {'user_2'});
    expect(await c.revoke(bob), isNull, reason: 'one change at a time');
    pending.complete(access(const [adaOwner]));
    await sharing;

    expect(c.busyKeys, isEmpty);
    expect(calls.where((call) => call.startsWith('revoke')), isEmpty);
  });

  test('a change answered after a load started wins over that load', () async {
    final slowLoad = Completer<PathAccess>();
    var loads = 0;
    final c = controller(
      load: () {
        loads++;
        return loads == 1
            ? Future.value(access(const [adaOwner, bobWriter]))
            : slowLoad.future;
      },
    );
    await c.load();

    final reloading = c.load();
    await c.share(family, AccessLevel.read);
    slowLoad.complete(access(const [adaOwner, bobWriter, everyoneFromTop]));
    await reloading;

    expect(c.grants, const [
      GrantItem(principal: ada, level: AccessLevel.owner),
    ]);
    expect(c.isLoading, isFalse);
  });

  test('reads the level set on the item itself', () async {
    final c = controller();
    await c.load();

    expect(c.directLevel(bob), AccessLevel.write);
    expect(c.directLevel(everyone), isNull, reason: 'inherited only');
  });

  test('an answer after dispose changes nothing', () async {
    final pending = Completer<PathAccess>();
    final c = controller(load: () => pending.future);

    final loading = c.load();
    c.dispose();
    pending.complete(access(const [adaOwner]));
    await loading;

    expect(c.hasLoaded, isFalse);
  });
}
