import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:quark/utils/photo_disk_cache_config.dart';

/// One on-device store of photo bytes (#4221), kept under a byte budget
/// rather than a count: written past it, the least recently used entries go
/// until it fits again.
///
/// A flutter_cache_manager store underneath, named [storeKey], whose bytes and
/// index outlive the app, so a photo opened yesterday opens today with no
/// network. Entries are written by the app, never fetched by the store, so
/// what a key holds is whatever was last written there; nothing is
/// revalidated.
///
/// Every operation is best effort: a disk that fails reads as a miss and
/// writes as a no-op, so the cache can only ever make a photo faster.
class PhotoDiskStore {
  /// A store kept in [repo] and [fileSystem], trimmed to [budgetBytes], which
  /// is read on every write so a new budget applies at once.
  PhotoDiskStore({
    required String storeKey,
    required CacheInfoRepository repo,
    required FileSystem fileSystem,
    required int Function() budgetBytes,
  }) : _repo = repo,
       _fileSystem = fileSystem,
       _budgetBytes = budgetBytes,
       _manager = CacheManager(
         Config(
           storeKey,
           stalePeriod: PhotoDiskCacheConfig.stalePeriod,
           maxNrOfCacheObjects: PhotoDiskCacheConfig.maxObjects,
           repo: repo,
           fileSystem: fileSystem,
         ),
       );

  final CacheManager _manager;
  final CacheInfoRepository _repo;
  final FileSystem _fileSystem;
  final int Function() _budgetBytes;

  /// The index, opened once alongside the manager's own connection to it.
  late final Future<CacheInfoRepository> _index = _repo.open().then(
    (_) => _repo,
  );

  /// Trims run one at a time, so two writes cannot both count the same
  /// entries and evict twice as much as either needed to.
  Future<void> _trimming = Future.value();

  /// The bytes under [key], or null when there are none or they cannot be
  /// read.
  Future<Uint8List?> read(String key) async {
    try {
      final info = await _manager.getFileFromCache(key);
      if (info == null) return null;
      return await info.file.readAsBytes();
    } on Exception {
      return null;
    }
  }

  /// Keeps [bytes] under [key], replacing whatever was there, and trims the
  /// store back to its budget. Bytes bigger than the whole budget are not
  /// kept: they would evict everything and then themselves.
  Future<void> write(String key, Uint8List bytes) async {
    if (bytes.lengthInBytes > _budgetBytes()) return;
    try {
      // The key stands in for the URL: the store never fetches, and a URL
      // would carry the session token onto the disk.
      await _manager.putFile(
        key,
        bytes,
        key: key,
        maxAge: PhotoDiskCacheConfig.stalePeriod,
      );
      // putFile leaves the length unset; record it so a trim need not read
      // the size of every file it holds.
      final index = await _index;
      final entry = await index.get(key);
      if (entry != null) {
        await index.update(entry.copyWith(length: bytes.lengthInBytes));
      }
    } on Exception {
      return;
    }
    await trim();
  }

  /// Drops [key].
  Future<void> remove(String key) async {
    try {
      await _manager.removeFile(key);
    } on Exception {
      // A file left behind is overwritten by the next write to its key.
    }
  }

  /// Drops every entry whose key passes [test].
  Future<void> removeWhere(bool Function(String key) test) async {
    try {
      final entries = await (await _index).getAllObjects();
      for (final entry in entries) {
        if (test(entry.key)) await remove(entry.key);
      }
    } on Exception {
      return;
    }
  }

  /// Drops every entry.
  Future<void> clear() async {
    try {
      await _manager.emptyCache();
    } on Exception {
      return;
    }
  }

  /// How many bytes the store holds.
  Future<int> sizeInBytes() async {
    try {
      final entries = await (await _index).getAllObjects();
      var total = 0;
      for (final entry in entries) {
        total += await _lengthOf(entry);
      }
      return total;
    } on Exception {
      return 0;
    }
  }

  /// Drops the least recently used entries until the store fits its budget.
  Future<void> trim() => _trimming = _trimming.then((_) => _trim());

  Future<void> _trim() async {
    try {
      final budget = _budgetBytes();
      final entries = await (await _index).getAllObjects();
      final lengths = <String, int>{
        for (final entry in entries) entry.key: await _lengthOf(entry),
      };
      var total = lengths.values.fold(0, (sum, length) => sum + length);
      if (total <= budget) return;
      // Oldest first; two touched in the same millisecond go in the order
      // they were first written.
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      entries.sort((a, b) {
        final byTouch = (a.touched ?? epoch).compareTo(b.touched ?? epoch);
        return byTouch != 0 ? byTouch : (a.id ?? 0).compareTo(b.id ?? 0);
      });
      for (final entry in entries) {
        if (total <= budget) break;
        await remove(entry.key);
        total -= lengths[entry.key]!;
      }
    } on Exception {
      return;
    }
  }

  Future<int> _lengthOf(CacheObject entry) async {
    final known = entry.length;
    if (known != null) return known;
    final file = await _fileSystem.createFile(entry.relativePath);
    return await file.exists() ? await file.length() : 0;
  }

  /// Closes the index, writing out anything it still holds in memory.
  Future<void> close() async {
    await _trimming;
    // Closing an index still opening fails inside the store, so wait for it.
    await _index;
    await _repo.close();
    await _manager.dispose();
  }
}
