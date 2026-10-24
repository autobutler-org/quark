import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/file_versions_controller.dart';
import 'package:quark/models/file_version.dart';
import 'package:quark/models/path_grant.dart';
import 'package:quark/utils/error_text.dart';

/// The version history sheet's state (#2992): the listing and its error, who
/// each version is credited to, and a restore that reloads the list.
void main() {
  final byAlice = FileVersion(
    id: 'v2',
    createdAt: DateTime.utc(2026, 10, 10, 9, 30),
    size: 1536,
    isNamed: true,
    label: 'Final draft',
    authorId: 7,
  );
  final bySystem = FileVersion(
    id: 'v1',
    createdAt: DateTime.utc(2026, 10, 9, 8),
    size: 900,
  );
  const principals = SharePrincipals(users: [(id: 7, username: 'alice')]);

  FileVersionsController build({
    ListFileVersionsFn? listVersions,
    RestoreFileVersionFn? restoreVersion,
    FileVersionContentFn? loadContent,
    LoadPrincipalsFn? loadPrincipals,
    int? selfUserId = 1,
  }) {
    final controller = FileVersionsController(
      path: 'Docs/notes.md',
      selfUserId: selfUserId,
      listVersions: listVersions ?? (_) async => [byAlice, bySystem],
      restoreVersion: restoreVersion ?? (_, _) async => bySystem,
      loadContent: loadContent ?? (_, _) async => Uint8List.fromList([1, 2]),
      loadPrincipals: loadPrincipals ?? () async => principals,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('loads the versions of its path and notifies once', () async {
    final paths = <String>[];
    final controller = build(
      listVersions: (path) async {
        paths.add(path);
        return [byAlice, bySystem];
      },
    );
    var notified = 0;
    controller.addListener(() => notified++);

    await controller.load();

    expect(paths, ['Docs/notes.md']);
    expect(controller.error, isNull);
    expect(controller.items.map((v) => v.id), [byAlice.id, bySystem.id]);
    expect(notified, 1);
  });

  test('maps versions to panel items with size and author', () async {
    final controller = build();
    await controller.load();

    final items = controller.items;
    expect(items.map((i) => i.id), ['v2', 'v1']);
    expect(items.first.createdAt, byAlice.createdAt);
    expect(items.first.sizeLabel, '1.5 KB');
    expect(items.first.author, 'alice');
    expect(items.first.label, 'Final draft');
    expect(items.first.isNamed, isTrue);
    expect(items.last.sizeLabel, '900 B');
    expect(items.last.author, 'System');
    expect(items.last.isNamed, isFalse);
  });

  test('credits the signed-in account as You, a stranger neutrally', () async {
    final controller = build(
      selfUserId: 7,
      listVersions: (_) async => [
        byAlice,
        FileVersion(
          id: 'v0',
          createdAt: DateTime.utc(2026),
          size: 1,
          authorId: 99,
        ),
      ],
    );
    await controller.load();

    expect(controller.items.map((i) => i.author), ['You', 'Unknown user']);
  });

  test('still lists versions when the names cannot be loaded', () async {
    final controller = build(
      loadPrincipals: () async => throw const ApiException(500),
    );

    await controller.load();

    expect(controller.error, isNull);
    expect(controller.items.first.author, 'Unknown user');
  });

  test('asks for the names once across reloads', () async {
    var asked = 0;
    final controller = build(
      loadPrincipals: () async {
        asked++;
        return principals;
      },
    );

    await controller.load();
    await controller.load();

    expect(asked, 1);
  });

  test('a failed load sets the error and keeps the last listing', () async {
    var fail = false;
    final controller = build(
      listVersions: (_) async =>
          fail ? throw const ApiException(404) : [byAlice],
    );
    await controller.load();
    fail = true;

    await controller.load();

    expect(controller.error, isA<ApiException>());
    expect(controller.items.map((v) => v.id), [byAlice.id]);
  });

  test('a slow earlier load never overwrites a newer one', () async {
    final slow = Completer<List<FileVersion>>();
    var calls = 0;
    final controller = build(
      listVersions: (_) => ++calls == 1 ? slow.future : Future.value([byAlice]),
    );

    final first = controller.load();
    await controller.load();
    slow.complete([bySystem]);
    await first;

    expect(controller.items.map((v) => v.id), [byAlice.id]);
  });

  test('restore marks the version busy, then reloads the list', () async {
    final restoring = Completer<FileVersion>();
    final restored = <String>[];
    var listings = 0;
    final controller = build(
      listVersions: (_) async {
        listings++;
        return [byAlice, bySystem];
      },
      restoreVersion: (path, id) {
        restored.add('$path@$id');
        return restoring.future;
      },
    );
    await controller.load();

    final result = controller.restore('v1');
    expect(controller.busyId, 'v1');
    expect(await controller.restore('v2'), isNull);
    restoring.complete(bySystem);

    expect(await result, isNull);
    expect(restored, ['Docs/notes.md@v1'], reason: 'one restore at a time');
    expect(listings, 2);
    expect(controller.busyId, isNull);
  });

  test('a refused restore returns the error and clears busy', () async {
    final controller = build(
      restoreVersion: (_, _) async => throw const ApiException(403),
    );
    await controller.load();

    final error = await controller.restore('v1');

    expect(error, isA<ApiException>());
    expect(controller.busyId, isNull);
    expect(controller.error, isNull, reason: 'the listing itself is fine');
  });

  test('content returns the bytes and clears busy, also on failure', () async {
    final controller = build();
    expect(await controller.content('v1'), [1, 2]);
    expect(controller.busyId, isNull);

    final failing = build(
      loadContent: (_, _) async => throw const ApiException(404),
    );
    await expectLater(failing.content('v1'), throwsA(isA<ApiException>()));
    expect(failing.busyId, isNull);
  });

  test('versionFor finds a version by id', () async {
    final controller = build();
    await controller.load();

    expect(controller.versionFor('v1'), bySystem);
    expect(controller.versionFor('nope'), isNull);
  });

  test('answers arriving after dispose are dropped quietly', () async {
    final listing = Completer<List<FileVersion>>();
    final restoring = Completer<FileVersion>();
    final controller = FileVersionsController(
      path: 'a.txt',
      listVersions: (_) => listing.future,
      restoreVersion: (_, _) => restoring.future,
      loadPrincipals: () async => principals,
    );

    final load = controller.load();
    final restore = controller.restore('v1');
    controller.dispose();
    listing.complete([byAlice]);
    restoring.complete(bySystem);

    await load;
    expect(await restore, isNull);
  });
}
