import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/file_browser_cache.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/utils/listing_snapshot_config.dart';
import 'package:quark/utils/listing_snapshot_store.dart';

/// A store that keeps its snapshots in memory, encoded the way the disk
/// would hold them, so a value JSON cannot carry fails here too.
class _FakeStore implements ListingSnapshotStore {
  final snapshots = <String, ({String scope, String encoded})>{};
  int reads = 0;
  int clears = 0;

  /// When set, a read waits on it before answering.
  Completer<void>? holdReads;

  @override
  Future<Object?> read(String name, {required String scope}) async {
    reads++;
    // Looked up before waiting: the real store queues its calls, so a read
    // answers with what was on disk when it was asked.
    final kept = snapshots[name];
    await holdReads?.future;
    if (kept == null) return null;
    if (kept.scope != scope) {
      snapshots.remove(name);
      return null;
    }
    return jsonDecode(kept.encoded);
  }

  @override
  Future<void> write(String name, Object? data, {required String scope}) async {
    snapshots[name] = (scope: scope, encoded: jsonEncode(data));
  }

  @override
  Future<void> clear() async {
    clears++;
    snapshots.clear();
  }
}

class _Changes extends ChangeNotifier {
  void fire() => notifyListeners();
}

FileNode _node(String name, {bool isDir = false}) => FileNode(
  name: name,
  size: 3,
  isDir: isDir,
  deviceName: 'Data',
  devicePath: '/quark/data',
  deviceSerial: '',
  dirPath: name,
  modifiedAt: DateTime.utc(2026, 1, 2),
);

void main() {
  final cache = FileBrowserCache.instance;

  setUp(cache.clearOpenFile);
  tearDown(cache.clearOpenFile);

  group('open-file tracking', () {
    test('nothing is open by default', () {
      expect(cache.isFileOpen('/notes.txt'), isFalse);
      expect(cache.openFilePath, isNull);
    });

    test('marking a file open then closed leaves nothing open', () {
      cache.markFileOpen('/report.pdf');
      expect(cache.isFileOpen('/report.pdf'), isTrue);

      cache.markFileClosed('/report.pdf');
      expect(cache.isFileOpen('/report.pdf'), isFalse);
      expect(cache.openFilePath, isNull);
    });

    // The whitespace case from #1604 — the reported trigger.
    test('a whitespace name round-trips the same as any other', () {
      cache.markFileOpen('/my doc.qdoc');
      expect(cache.isFileOpen('/my doc.qdoc'), isTrue);

      cache.markFileClosed('/my doc.qdoc');
      expect(cache.isFileOpen('/my doc.qdoc'), isFalse);
      expect(cache.openFilePath, isNull);
    });

    // markFileOpen stored the raw path while the didUpdateWidget guard looked
    // it up normalized, so the two call sites never agreed on the key (#1604).
    test('keys are normalized so callers cannot disagree on the format', () {
      cache.markFileOpen('my doc.qdoc');
      expect(cache.isFileOpen('/my doc.qdoc'), isTrue);
      expect(cache.isFileOpen('my doc.qdoc'), isTrue);
      expect(cache.openFilePath, '/my doc.qdoc');

      cache.markFileClosed('my doc.qdoc');
      expect(cache.isFileOpen('/my doc.qdoc'), isFalse);
    });

    test('trailing slashes and surrounding whitespace normalize alike', () {
      cache.markFileOpen('  /folder/my doc.qdoc  ');
      expect(cache.isFileOpen('/folder/my doc.qdoc'), isTrue);
    });

    test('a different file is not reported open', () {
      cache.markFileOpen('/a.qdoc');
      expect(cache.isFileOpen('/b.qdoc'), isFalse);
    });

    test('closing a different path leaves the marker alone', () {
      cache.markFileOpen('/a.qdoc');
      cache.markFileClosed('/b.qdoc');
      expect(cache.isFileOpen('/a.qdoc'), isTrue);
    });

    test('an empty path is never reported open while nothing is open', () {
      expect(cache.isFileOpen(''), isFalse);
    });
  });

  // What a cold launch shows before the first listing answers (#1781).
  group('listing snapshot', () {
    late _FakeStore store;
    late _Changes changes;
    ({String host, String username})? account;

    FileBrowserCache newCache() => FileBrowserCache(
      store: store,
      account: () => account,
      accountChanges: changes,
    );

    List<String>? names(FileBrowserCache cache, String path) =>
        cache.get(path)?.map((node) => node.name).toList();

    setUp(() {
      store = _FakeStore();
      changes = _Changes();
      account = (host: 'https://quark.local', username: 'ada');
    });

    test('a landing listing is there after the next launch hydrates', () async {
      newCache()
        ..put('', [_node('users', isDir: true), _node('a.txt')])
        ..put('/users/ada', [_node('notes.qdoc')]);
      await pumpEventQueue();

      final relaunched = newCache();
      expect(relaunched.get(''), isNull);
      await relaunched.hydrate();

      expect(names(relaunched, ''), ['users', 'a.txt']);
      expect(names(relaunched, '/users/ada'), ['notes.qdoc']);
      expect(relaunched.get('')!.first.isDir, isTrue);
      expect(relaunched.get('')!.first.modifiedAt, DateTime.utc(2026, 1, 2));
    });

    test('a folder a cold launch never opens is not written', () async {
      newCache()
        ..put('/photos', [_node('a.jpg')])
        ..put('/users/grace', [_node('hers.txt')]);
      await pumpEventQueue();

      expect(store.snapshots, isEmpty);
    });

    test('no more than the cap is written for a folder', () async {
      newCache().put('', [
        for (var i = 0; i < ListingSnapshotConfig.maxItemsPerFolder + 5; i++)
          _node('f$i.txt'),
      ]);
      await pumpEventQueue();

      final relaunched = newCache();
      await relaunched.hydrate();
      expect(
        relaunched.get(''),
        hasLength(ListingSnapshotConfig.maxItemsPerFolder),
      );
      expect(relaunched.get('')!.first.name, 'f0.txt');
    });

    test('signing out forgets the snapshot and the listings', () async {
      final cache = newCache()..put('', [_node('a.txt')]);
      await pumpEventQueue();
      expect(store.snapshots, isNotEmpty);

      account = null;
      changes.fire();
      await pumpEventQueue();

      expect(store.snapshots, isEmpty);
      expect(cache.get(''), isNull);
    });

    test('another account on the same Quark sees nothing', () async {
      final cache = newCache()..put('', [_node('a.txt')]);
      await pumpEventQueue();

      account = (host: 'https://quark.local', username: 'grace');

      expect(cache.get(''), isNull);
      await cache.hydrate();
      expect(cache.get(''), isNull);
      expect(store.snapshots, isEmpty);
    });

    test('another Quark sees nothing', () async {
      newCache().put('', [_node('a.txt')]);
      await pumpEventQueue();

      // A fresh cache: the app was closed before it switched Quarks.
      account = (host: 'https://other.local', username: 'ada');
      final relaunched = newCache();
      await relaunched.hydrate();

      expect(relaunched.get(''), isNull);
      expect(store.snapshots, isEmpty);
    });

    test('clear forgets the snapshot too', () async {
      final cache = newCache()..put('', [_node('a.txt')]);
      await pumpEventQueue();

      cache.clear();
      await pumpEventQueue();

      expect(store.snapshots, isEmpty);
      expect(cache.get(''), isNull);
      await cache.hydrate();
      expect(cache.get(''), isNull);
    });

    test('a snapshot of the wrong shape is cleared and ignored', () async {
      store.snapshots['files'] = (
        scope: 'https://quark.local\u0000ada',
        encoded: '{"": "not a listing", "/users/ada": [1, 2]}',
      );

      final cache = newCache();
      await cache.hydrate();
      await pumpEventQueue();

      expect(cache.get(''), isNull);
      expect(cache.get('/users/ada'), isNull);
      expect(store.snapshots, isEmpty);
    });

    test('a listing fetched this session wins over the snapshot', () async {
      newCache()
        ..put('', [_node('stale.txt')])
        ..put('/users/ada', [_node('kept.txt')]);
      await pumpEventQueue();

      final relaunched = newCache();
      store.holdReads = Completer<void>();
      final hydrated = relaunched.hydrate();
      relaunched.put('', [_node('fresh.txt')]);
      store.holdReads!.complete();
      await hydrated;

      expect(names(relaunched, ''), ['fresh.txt']);
      expect(names(relaunched, '/users/ada'), ['kept.txt']);
    });

    test('a snapshot read across a clear is dropped', () async {
      newCache().put('', [_node('a.txt')]);
      await pumpEventQueue();

      final relaunched = newCache();
      store.holdReads = Completer<void>();
      final hydrated = relaunched.hydrate();
      relaunched.clear();
      store.holdReads!.complete();
      await hydrated;

      expect(relaunched.get(''), isNull);
    });

    test('hydrating twice reads the disk once', () async {
      final cache = newCache();
      await cache.hydrate();
      await cache.hydrate();

      expect(store.reads, 1);
    });

    test('hydrating with nobody signed in clears the store', () async {
      store.snapshots['files'] = (
        scope: 'https://quark.local\u0000ada',
        encoded: '{"": []}',
      );
      account = null;

      final cache = newCache();
      await cache.hydrate();

      expect(store.snapshots, isEmpty);
      expect(store.reads, 0);
      expect(cache.get(''), isNull);
    });

    test('with nobody signed in listings stay in memory only', () async {
      account = null;
      final cache = newCache()..put('', [_node('a.txt')]);
      await pumpEventQueue();

      expect(names(cache, ''), ['a.txt']);
      expect(store.snapshots, isEmpty);
    });

    test('the snapshot holds listing fields and nothing else', () async {
      newCache().put('', [_node('a.txt')]);
      await pumpEventQueue();

      final kept = store.snapshots['files']!;
      expect(kept.scope, 'https://quark.local\u0000ada');
      final data = jsonDecode(kept.encoded) as Map<String, dynamic>;
      expect(data.keys, ['']);
      expect(((data[''] as List).single as Map).keys.toSet(), {
        'name',
        'size',
        'compressedSize',
        'isDir',
        'deviceName',
        'devicePath',
        'deviceSerial',
        'dirPath',
        'fileType',
        'modifiedAt',
      });
    });

    test('the open-file marker outlives a change of account', () {
      final cache = newCache()..markFileOpen('/a.qdoc');

      account = (host: 'https://quark.local', username: 'grace');
      cache.get('');
      cache.clear();

      expect(cache.isFileOpen('/a.qdoc'), isTrue);
    });
  });
}
