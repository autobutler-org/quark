import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:quark/services/photo_disk_store.dart';

/// A [PhotoDiskStore] for a test: its bytes in [files], in memory, and its
/// index in a JSON file under [index], a real directory, so a second store
/// made on the same two finds what the first wrote, as the app does after a
/// restart.
PhotoDiskStore memoryPhotoDiskStore(
  Directory index,
  MemoryCacheSystem files, {
  String storeKey = 'testPhotos',
  int Function()? budgetBytes,
}) => PhotoDiskStore(
  storeKey: storeKey,
  repo: JsonCacheInfoRepository.withFile(File('${index.path}/$storeKey.json')),
  fileSystem: files,
  budgetBytes: budgetBytes ?? () => 1 << 30,
);
