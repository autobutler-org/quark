import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/photo_disk_cache.dart';
import 'package:quark/services/photo_disk_store.dart';
import 'package:quark/services/photo_preview_service.dart';
import 'package:quark/utils/photo_disk_cache_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_quark_http.dart';
import '../support/photo_disk_stores.dart';
import '../support/secure_storage.dart';

/// #4221: photos the viewer opened are kept on this device, so they open
/// again after a restart with no network, and leave with the account.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  useFakeQuark();

  final stored = <String, String>{};
  final settings = AppSettings.instance;
  final photo = Uint8List.fromList([0xff, 0xd8, 1, 2, 3]);

  late Directory index;
  late MemoryCacheSystem previewFiles;
  late MemoryCacheSystem originalFiles;
  late MemoryCacheSystem keptFiles;
  final open = <PhotoDiskStore>[];

  /// Opens both stores as the app does at launch: a second call finds what
  /// the first wrote, as a restart does.
  void launch() {
    final previews = memoryPhotoDiskStore(
      index,
      previewFiles,
      storeKey: 'previews',
    );
    final originals = memoryPhotoDiskStore(
      index,
      originalFiles,
      storeKey: 'originals',
    );
    final keptPreviews = memoryPhotoDiskStore(
      index,
      keptFiles,
      storeKey: 'keptPreviews',
    );
    final keptOriginals = memoryPhotoDiskStore(
      index,
      keptFiles,
      storeKey: 'keptOriginals',
    );
    open.addAll([previews, originals, keptPreviews, keptOriginals]);
    PhotoDiskCache.previews = Future.value(previews);
    PhotoDiskCache.originals = Future.value(originals);
    PhotoDiskCache.keptPreviews = Future.value(keptPreviews);
    PhotoDiskCache.keptOriginals = Future.value(keptOriginals);
  }

  /// Closes the stores, writing out their index, as the app does on exit.
  Future<void> quit() async {
    for (final store in open) {
      await store.close();
    }
    open.clear();
  }

  /// No network: every request fails as it does in airplane mode.
  void goOffline() => answerWith(
    (request) => throw http.ClientException('network is unreachable'),
  );

  setUpAll(() => mockSecureStorage(stored));

  setUp(() async {
    stored.clear();
    SharedPreferences.setMockInitialValues({});
    await settings.load();
    await settings.addHost(
      HostEntry(name: 'Home', hostAddress: 'https://quark.local'),
    );
    await settings.setUsername('ada');
    await settings.setSessionToken('token-a');
    index = await Directory.systemTemp.createTemp('photo_disk_cache');
    previewFiles = MemoryCacheSystem();
    originalFiles = MemoryCacheSystem();
    keptFiles = MemoryCacheSystem();
    launch();
  });

  tearDown(() async {
    await quit();
    await index.delete(recursive: true);
  });

  test('a photo opened in the last session opens with no network', () async {
    answerWith((_) => http.Response.bytes(photo, 200));
    expect(await FilesService.downloadFileBytes('photos/beach.jpg'), photo);

    await quit();
    launch();
    goOffline();
    requests.clear();

    expect(await FilesService.downloadFileBytes('photos/beach.jpg'), photo);
    expect(requests, isEmpty);
  });

  test('a viewer preview is kept among the previews and opens with no '
      'network, never passing for the original', () async {
    answerWith((_) => http.Response.bytes(photo, 200));
    expect(
      await PhotoPreviewService.downloadPreviewBytes('photos/beach.jpg'),
      photo,
    );
    expect(await (await PhotoDiskCache.originals)!.sizeInBytes(), 0);

    goOffline();
    expect(
      await PhotoPreviewService.downloadPreviewBytes('photos/beach.jpg'),
      photo,
    );
    await expectLater(
      FilesService.downloadFileBytes('photos/beach.jpg'),
      throwsA(anything),
    );
  });

  test('a HEIC is kept among the previews, not the originals', () async {
    answerWith((_) => http.Response.bytes(photo, 200));
    await FilesService.downloadFileBytes('photos/sunset.heic');

    expect(await (await PhotoDiskCache.originals)!.sizeInBytes(), 0);
    expect(await (await PhotoDiskCache.previews)!.sizeInBytes(), photo.length);
    goOffline();
    expect(await FilesService.downloadFileBytes('photos/sunset.heic'), photo);
  });

  test('a file that is not a photo is never kept', () async {
    answerWith((_) => http.Response.bytes(photo, 200));
    await FilesService.downloadFileBytes('books/novel.pdf');

    expect(await PhotoDiskCache.sizeInBytes(), 0);
  });

  test('signing in again finds the photo already kept', () async {
    answerWith((_) => http.Response.bytes(photo, 200));
    await FilesService.downloadFileBytes('photos/beach.jpg');
    await settings.setSessionToken('token-b');
    goOffline();

    expect(await FilesService.downloadFileBytes('photos/beach.jpg'), photo);
    expect(PhotoDiskCache.keyFor('photos/beach.jpg'), isNot(contains('token')));
  });

  test('rotating a photo drops the copy kept on this device', () async {
    answerWith((_) => http.Response.bytes(photo, 200));
    await FilesService.downloadFileBytes('photos/beach.jpg');

    answerWith((_) => http.Response('{}', 200));
    await FilesService.rotatePhoto('photos/beach.jpg', rotationQuarters: 1);

    expect(await PhotoDiskCache.sizeInBytes(), 0);
  });

  test('clear empties both stores', () async {
    answerWith((_) => http.Response.bytes(photo, 200));
    await FilesService.downloadFileBytes('photos/beach.jpg');
    await FilesService.downloadFileBytes('photos/sunset.heic');

    await PhotoDiskCache.clear();

    expect(await PhotoDiskCache.sizeInBytes(), 0);
  });

  test("forgetting an account drops only that account's photos", () async {
    answerWith((_) => http.Response.bytes(photo, 200));
    await FilesService.downloadFileBytes('photos/ada.jpg');
    await settings.setUsername('grace');
    await FilesService.downloadFileBytes('photos/grace.jpg');

    await PhotoDiskCache.forget(host: 'https://quark.local', account: 'ada');

    goOffline();
    expect(await FilesService.downloadFileBytes('photos/grace.jpg'), photo);
    await settings.setUsername('ada');
    await expectLater(
      FilesService.downloadFileBytes('photos/ada.jpg'),
      throwsA(anything),
    );
  });

  test('removing a Quark drops every one of its photos', () async {
    answerWith((_) => http.Response.bytes(photo, 200));
    await FilesService.downloadFileBytes('photos/beach.jpg');

    await settings.removeHost(settings.activeIndex);

    expect(await PhotoDiskCache.sizeInBytes(), 0);
  });

  test('the preview budget picked in Settings outlives a restart', () async {
    expect(
      settings.photoPreviewCacheBytes.value,
      PhotoDiskCacheConfig.defaultPreviewBudgetBytes,
    );
    const picked = 256 * 1024 * 1024;
    await settings.setPhotoPreviewCacheBytes(picked);

    await settings.load();

    expect(settings.photoPreviewCacheBytes.value, picked);
  });

  group('kept albums (#4222)', () {
    Future<Uint8List?> download() async => photo;

    test('a kept photo opens with no network after a restart, and the cache '
        'neither counts nor clears it', () async {
      final kept = await PhotoDiskCache.keep(
        'photos/beach.jpg',
        rendition: KeptRendition.preview,
        download: download,
      );
      expect(kept, photo.length);
      expect(await PhotoDiskCache.sizeInBytes(), 0);
      await PhotoDiskCache.clear();

      await quit();
      launch();
      goOffline();
      expect(
        await PhotoPreviewService.downloadPreviewBytes('photos/beach.jpg'),
        photo,
      );
    });

    test('keeping a photo already cached moves it out of the budget with '
        'no download', () async {
      answerWith((_) => http.Response.bytes(photo, 200));
      await FilesService.downloadFileBytes('photos/beach.jpg');
      expect(await PhotoDiskCache.sizeInBytes(), photo.length);

      final kept = await PhotoDiskCache.keep(
        'photos/beach.jpg',
        rendition: KeptRendition.original,
        download: () => fail('downloaded a photo already on the device'),
      );

      expect(kept, photo.length);
      expect(await PhotoDiskCache.sizeInBytes(), 0);
      expect(
        await PhotoDiskCache.keptLength(
          'photos/beach.jpg',
          rendition: KeptRendition.original,
        ),
        photo.length,
      );
    });

    test('releasing a kept photo frees its bytes', () async {
      await PhotoDiskCache.keep(
        'photos/beach.jpg',
        rendition: KeptRendition.original,
        download: download,
      );

      await PhotoDiskCache.release(
        'photos/beach.jpg',
        rendition: KeptRendition.original,
      );

      expect(
        await PhotoDiskCache.keptLength(
          'photos/beach.jpg',
          rendition: KeptRendition.original,
        ),
        isNull,
      );
      expect(await (await PhotoDiskCache.keptOriginals)!.sizeInBytes(), 0);
    });

    test('forgetting an account drops its kept photos too', () async {
      await PhotoDiskCache.keep(
        'photos/beach.jpg',
        rendition: KeptRendition.preview,
        download: download,
      );

      await PhotoDiskCache.forget(host: 'https://quark.local', account: 'ada');

      expect(
        await PhotoDiskCache.keptLength(
          'photos/beach.jpg',
          rendition: KeptRendition.preview,
        ),
        isNull,
      );
    });
  });
}
