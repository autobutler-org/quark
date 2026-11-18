import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/photo_disk_store.dart';

import '../support/photo_disk_stores.dart';

/// #4221: a store of photo bytes on the device, bounded by bytes rather than
/// a count, that outlives the app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory index;
  late MemoryCacheSystem files;
  var budget = 1000;
  final open = <PhotoDiskStore>[];

  PhotoDiskStore store() {
    final s = memoryPhotoDiskStore(index, files, budgetBytes: () => budget);
    open.add(s);
    return s;
  }

  setUp(() async {
    index = await Directory.systemTemp.createTemp('photo_disk_store');
    files = MemoryCacheSystem();
    budget = 1000;
  });

  tearDown(() async {
    for (final s in open) {
      await s.close();
    }
    open.clear();
    await index.delete(recursive: true);
  });

  Uint8List bytes(int length, [int fill = 1]) =>
      Uint8List.fromList(List.filled(length, fill));

  test('a photo written is read back', () async {
    final s = store();
    await s.write('a', bytes(10, 7));
    expect(await s.read('a'), bytes(10, 7));
    expect(await s.read('missing'), isNull);
  });

  test('a photo written before a restart is read after it', () async {
    final before = store();
    await before.write('a', bytes(10, 7));
    await before.close();
    open.remove(before);

    expect(await store().read('a'), bytes(10, 7));
  });

  test('the least recently used photos go once the budget is spent', () async {
    final s = store();
    await s.write('a', bytes(400));
    await s.write('b', bytes(400));
    await s.write('c', bytes(400));

    expect(await s.read('a'), isNull);
    expect(await s.read('b'), isNotNull);
    expect(await s.read('c'), isNotNull);
    expect(await s.sizeInBytes(), 800);
  });

  test('a photo bigger than the whole budget is not kept', () async {
    final s = store();
    await s.write('a', bytes(400));
    await s.write('huge', bytes(1001));

    expect(await s.read('huge'), isNull);
    expect(await s.read('a'), isNotNull);
  });

  test('a smaller budget trims what is already there', () async {
    final s = store();
    await s.write('a', bytes(400));
    await s.write('b', bytes(400));

    budget = 500;
    await s.trim();

    expect(await s.read('a'), isNull);
    expect(await s.read('b'), isNotNull);
  });

  test('clear empties the store', () async {
    final s = store();
    await s.write('a', bytes(10));
    await s.write('b', bytes(10));

    await s.clear();

    expect(await s.read('a'), isNull);
    expect(await s.read('b'), isNull);
    expect(await s.sizeInBytes(), 0);
  });

  test('removeWhere drops only the matching keys', () async {
    final s = store();
    await s.write('keep', bytes(10));
    await s.write('drop-1', bytes(10));
    await s.write('drop-2', bytes(10));

    await s.removeWhere((key) => key.startsWith('drop'));

    expect(await s.read('keep'), isNotNull);
    expect(await s.read('drop-1'), isNull);
    expect(await s.read('drop-2'), isNull);
  });
}
