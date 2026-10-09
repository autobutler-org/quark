import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/listing_snapshot_config.dart';
import 'package:quark/utils/listing_snapshot_store_io.dart';

void main() {
  late Directory root;
  late IoListingSnapshotStore store;

  File fileFor(String name) => File('${root.path}/$name.json');

  setUp(() async {
    final temp = await Directory.systemTemp.createTemp('listing_snapshot');
    // The store creates its directory itself; start without one.
    root = Directory('${temp.path}/${ListingSnapshotConfig.directoryName}');
    store = IoListingSnapshotStore(root: () async => root);
    addTearDown(() => temp.delete(recursive: true));
  });

  test('what is written for a scope reads back for that scope', () async {
    await store.write('files', {
      '': [
        {'name': 'a.txt'},
      ],
    }, scope: 'quark\u0000ada');

    expect(await store.read('files', scope: 'quark\u0000ada'), {
      '': [
        {'name': 'a.txt'},
      ],
    });
    // A second store on the same directory is the next launch.
    final relaunched = IoListingSnapshotStore(root: () async => root);
    expect(await relaunched.read('files', scope: 'quark\u0000ada'), {
      '': [
        {'name': 'a.txt'},
      ],
    });
  });

  test('nothing written reads as null', () async {
    expect(await store.read('files', scope: 'quark\u0000ada'), isNull);
  });

  test('another scope reads null and the file is deleted', () async {
    await store.write('files', {'': <Object>[]}, scope: 'quark\u0000ada');

    expect(await store.read('files', scope: 'quark\u0000grace'), isNull);
    expect(await fileFor('files').exists(), isFalse);
    expect(await store.read('files', scope: 'quark\u0000ada'), isNull);
  });

  test('a corrupt file is deleted and ignored', () async {
    await root.create(recursive: true);
    await fileFor('files').writeAsString('{"scope": "quark\u0000ada", "da');

    expect(await store.read('files', scope: 'quark\u0000ada'), isNull);
    expect(await fileFor('files').exists(), isFalse);
  });

  test('a file of the wrong shape is deleted and ignored', () async {
    await root.create(recursive: true);
    await fileFor('files').writeAsString('["not", "an", "envelope"]');

    expect(await store.read('files', scope: 'quark\u0000ada'), isNull);
    expect(await fileFor('files').exists(), isFalse);
  });

  test('an oversized file on disk is deleted unread', () async {
    await root.create(recursive: true);
    await fileFor(
      'files',
    ).writeAsString('"${'x' * ListingSnapshotConfig.maxBytes}"');

    expect(await store.read('files', scope: 'quark\u0000ada'), isNull);
    expect(await fileFor('files').exists(), isFalse);
  });

  test('oversized data is not written and drops what was there', () async {
    await store.write('files', {'': <Object>[]}, scope: 'quark\u0000ada');

    await store.write(
      'files',
      'x' * ListingSnapshotConfig.maxBytes,
      scope: 'quark\u0000ada',
    );

    expect(await fileFor('files').exists(), isFalse);
    expect(await store.read('files', scope: 'quark\u0000ada'), isNull);
  });

  test('clear removes every snapshot', () async {
    await store.write('files', {'': <Object>[]}, scope: 'quark\u0000ada');
    await store.write('photos', <Object>[], scope: 'quark\u0000ada');

    await store.clear();

    expect(await root.exists(), isFalse);
    expect(await store.read('files', scope: 'quark\u0000ada'), isNull);
    expect(await store.read('photos', scope: 'quark\u0000ada'), isNull);
  });

  test('a write queued before clear does not survive it', () async {
    // Neither is awaited before the next is issued: signing out must win
    // over a write that was already on its way to disk.
    final written = store.write('files', {
      '': <Object>[],
    }, scope: 'quark\u0000ada');
    final cleared = store.clear();
    await Future.wait([written, cleared]);

    expect(await root.exists(), isFalse);
  });

  test('the same data can be written again after clear', () async {
    await store.write('files', {'': <Object>[]}, scope: 'quark\u0000ada');
    await store.clear();

    await store.write('files', {'': <Object>[]}, scope: 'quark\u0000ada');

    expect(await store.read('files', scope: 'quark\u0000ada'), {
      '': <Object>[],
    });
  });

  test('an unchanged write does not rewrite the file', () async {
    await store.write('files', {'': <Object>[]}, scope: 'quark\u0000ada');
    // Gone behind the store's back: only a real write would bring it back.
    await fileFor('files').delete();

    await store.write('files', {'': <Object>[]}, scope: 'quark\u0000ada');
    expect(await fileFor('files').exists(), isFalse);

    await store.write('files', {
      '': [
        {'name': 'new.txt'},
      ],
    }, scope: 'quark\u0000ada');
    expect(await fileFor('files').exists(), isTrue);
  });

  test(
    'a root that cannot be resolved reads null and writes nothing',
    () async {
      final unresolved = IoListingSnapshotStore(
        root: () async => throw StateError('no path provider'),
      );

      await unresolved.write('files', {
        '': <Object>[],
      }, scope: 'quark\u0000ada');
      expect(await unresolved.read('files', scope: 'quark\u0000ada'), isNull);
      await unresolved.clear();
    },
  );
}
