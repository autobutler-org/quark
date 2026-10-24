import 'package:quark/utils/cache_manager_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:quark/utils/decode_once_image.dart';
import 'package:quark/utils/thumbnail_cache_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secure_storage.dart';

/// Records what [ThumbnailCacheManager.evict] drops from disk.
class _RecordingCacheManager extends Fake implements BaseCacheManager {
  final removed = <String>[];

  @override
  Future<void> removeFile(String key) async => removed.add(key);
}

/// A store whose index cannot be read.
class _BrokenCacheManager extends Fake implements BaseCacheManager {
  @override
  Future<void> removeFile(String key) async => throw Exception('disk');
}

/// An image that never arrives, enough to occupy a slot in the image cache.
class _PendingImage extends ImageStreamCompleter {}

/// #1777: thumbnails keep one disk cache entry per Quark, account and file,
/// whatever the session token is.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final stored = <String, String>{};
  final settings = AppSettings.instance;

  setUpAll(() {
    mockSecureStorage(stored);
  });

  setUp(() async {
    stored.clear();
    SharedPreferences.setMockInitialValues({});
    await settings.load();
    await settings.addHost(
      HostEntry(name: 'Home', hostAddress: 'https://quark.local'),
    );
    await settings.setUsername('ada');
    await settings.setSessionToken('token-a');
  });

  Uri thumbnail({String? size}) =>
      FilesService.constructThumbnailUrl('/photos/beach.jpg', size: size);

  test('signing in again keeps the key while the URL changes', () async {
    final before = thumbnail();
    final keyBefore = ThumbnailCacheManager.keyFor(before);

    await settings.setSessionToken('token-b');
    final after = thumbnail();

    expect(after, isNot(before));
    expect(ThumbnailCacheManager.keyFor(after), keyBefore);
    expect(keyBefore, isNot(contains('token-a')));
  });

  test('another account on the same Quark gets its own key', () async {
    final ada = ThumbnailCacheManager.keyFor(thumbnail());
    await settings.setUsername('grace');
    expect(ThumbnailCacheManager.keyFor(thumbnail()), isNot(ada));
  });

  test('another Quark gets its own key', () async {
    final home = ThumbnailCacheManager.keyFor(thumbnail());
    // Adding a Quark switches to it.
    await settings.addHost(
      HostEntry(name: 'Cabin', hostAddress: 'https://cabin.local'),
    );
    await settings.setUsername('ada');
    expect(ThumbnailCacheManager.keyFor(thumbnail()), isNot(home));
  });

  test('evict drops the bytes on disk and every decoded image', () async {
    final url = thumbnail(size: 'sm');
    final key = ThumbnailCacheManager.keyFor(url);
    final provider = CacheManagerImage(
      url.toString(),
      cacheKey: key,
      cacheManager: _RecordingCacheManager(),
    );
    final resized = ResizeImage(
      provider,
      width: ThumbnailCacheConfig.memCacheWidth,
    );
    // The file browser decodes at full size; the photo grid bounds the width
    // and decodes once (#3366).
    final cacheKeys = [
      await provider.obtainKey(ImageConfiguration.empty),
      await resized.obtainKey(ImageConfiguration.empty),
      await DecodeOnceImage(resized).obtainKey(ImageConfiguration.empty),
    ];
    final imageCache = PaintingBinding.instance.imageCache;
    for (final cacheKey in cacheKeys) {
      imageCache.putIfAbsent(cacheKey, _PendingImage.new);
      expect(imageCache.containsKey(cacheKey), isTrue);
    }

    final manager = _RecordingCacheManager();
    await ThumbnailCacheManager.evict(url, manager: manager);

    expect(manager.removed, [key]);
    for (final cacheKey in cacheKeys) {
      expect(imageCache.containsKey(cacheKey), isFalse);
    }
  });

  test('evict still drops the decoded image when the disk fails', () async {
    final url = thumbnail();
    final cacheKey = await CacheManagerImage(
      url.toString(),
      cacheKey: ThumbnailCacheManager.keyFor(url),
      cacheManager: _BrokenCacheManager(),
    ).obtainKey(ImageConfiguration.empty);
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.putIfAbsent(cacheKey, _PendingImage.new);

    await ThumbnailCacheManager.evict(url, manager: _BrokenCacheManager());

    expect(imageCache.containsKey(cacheKey), isFalse);
  });
}
