import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:quark/utils/thumbnail_cache_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final stored = <String, String>{};
  final settings = AppSettings.instance;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async {
          final key = call.arguments['key'] as String?;
          switch (call.method) {
            case 'read':
              return stored[key];
            case 'write':
              stored[key!] = call.arguments['value'] as String;
            case 'delete':
              stored.remove(key);
          }
          return null;
        });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
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

  test('evict drops the bytes on disk and both decoded images', () async {
    final url = thumbnail(size: 'sm');
    final key = ThumbnailCacheManager.keyFor(url);
    final provider = CachedNetworkImageProvider(url.toString(), cacheKey: key);
    // The file browser decodes at full size; the photo grid bounds the width.
    final cacheKeys = [
      await provider.obtainKey(ImageConfiguration.empty),
      await ResizeImage(
        provider,
        width: ThumbnailCacheConfig.memCacheWidth,
      ).obtainKey(ImageConfiguration.empty),
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
    final cacheKey = await CachedNetworkImageProvider(
      url.toString(),
      cacheKey: ThumbnailCacheManager.keyFor(url),
    ).obtainKey(ImageConfiguration.empty);
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.putIfAbsent(cacheKey, _PendingImage.new);

    await ThumbnailCacheManager.evict(url, manager: _BrokenCacheManager());

    expect(imageCache.containsKey(cacheKey), isFalse);
  });
}
