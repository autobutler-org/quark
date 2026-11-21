import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quark/services/photo_disk_store.dart';
import 'package:quark/utils/backup_exclusion.dart';
import 'package:quark/utils/photo_disk_cache_config.dart';

/// iOS, Android and desktop: opens the [PhotoDiskStore] named [storeKey], or
/// null when the platform gives the app no cache directory. Entries nobody
/// opens for [stalePeriod] go, a year when it is null.
///
/// Everything it keeps, bytes and index alike, sits in one folder in the
/// app's private cache directory: the app's own `Library/Caches` on iOS,
/// marked to stay out of iCloud backup, and its internal cache directory on
/// Android, which Google backup never copies. Nothing is written to a shared
/// folder or the system photo library.
Future<PhotoDiskStore?> openPhotoDiskStorePlatform(
  String storeKey, {
  required int Function() budgetBytes,
  Duration? stalePeriod,
}) {
  // Under `flutter test` there is no platform to ask for a folder, and a test
  // must not write photos into the developer's own cache; a test that wants
  // a store sets `PhotoDiskCache.originals` or `previews` to one of its own.
  // Complete before anyone awaits it, not async: the future outlives the test that first
  // reads it, and one still pending in that test's fake clock would never
  // complete for the tests after it.
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return SynchronousFuture(null);
  }
  return _open(storeKey, budgetBytes: budgetBytes, stalePeriod: stalePeriod);
}

Future<PhotoDiskStore?> _open(
  String storeKey, {
  required int Function() budgetBytes,
  Duration? stalePeriod,
}) async {
  try {
    // flutter_cache_manager's IOFileSystem keeps the bytes in the same
    // folder, `<temporary directory>/<storeKey>`.
    final base = await getTemporaryDirectory();
    final folder = Directory('${base.path}/$storeKey');
    await folder.create(recursive: true);
    await excludeFromBackup(folder.path);
    // The index beside the bytes, not in the database directory the store
    // defaults to, which iOS backs up.
    final mobile = Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
    final repo = mobile
        ? CacheObjectProvider(path: '${folder.path}/$storeKey.db')
        : JsonCacheInfoRepository(path: '${folder.path}/$storeKey.json');
    return PhotoDiskStore(
      storeKey: storeKey,
      repo: repo,
      fileSystem: IOFileSystem(storeKey),
      budgetBytes: budgetBytes,
      stalePeriod: stalePeriod ?? PhotoDiskCacheConfig.stalePeriod,
    );
  } catch (_) {
    // Best effort: with no folder, photos are fetched every time as before.
    return null;
  }
}
