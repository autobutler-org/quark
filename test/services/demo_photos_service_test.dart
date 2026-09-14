import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/demo_photos_service.dart';
import 'package:quark/utils/error_text.dart';

/// #1746: the sample library is hand-listed Dart pointing at bundled files, so
/// the two can drift apart silently — a renamed asset would only show up as a
/// grey tile in a demo. These pin the catalog to the bundle, and the demo
/// controller to the catalog.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final photos = DemoPhotosService.photos;

  // The test platform is Android, so the controller also asks photo_manager
  // for the device library. With no plugin behind the channel that call never
  // answers; failing it leaves the device list empty.
  const photoManager = MethodChannel('com.fluttercandies/photo_manager');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          photoManager,
          (_) async => throw MissingPluginException(),
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(photoManager, null);
  });

  tearDown(() => AppSettings.instance.setDemoMode(false));

  test('follows the demo mode switch', () async {
    expect(DemoPhotosService.isEnabled, isFalse);

    await AppSettings.instance.setDemoMode(true);

    expect(DemoPhotosService.isEnabled, isTrue);
  });

  test('every listed photo is a bundled asset', () async {
    expect(photos, isNotEmpty);
    for (final photo in photos) {
      expect(photo.relPath, startsWith('${DemoPhotosService.assetDir}/'));
      expect(photo.relPath, endsWith('/${photo.fileName}'));
      final bytes = await DemoPhotosService.loadBytes(photo.relPath);
      expect(bytes, isNotEmpty, reason: '${photo.relPath} is not bundled');
    }
  });

  test('every photo carries the demo serial', () {
    for (final photo in photos) {
      expect(DemoPhotosService.isDemoSerial(photo.serial), isTrue);
    }
    expect(DemoPhotosService.isDemoSerial(''), isFalse);
    expect(DemoPhotosService.isDemoSerial('ABC123'), isFalse);
    expect(DemoPhotosService.isDemoSerial(null), isFalse);
  });

  test(
    'a single page covers the whole library, so nothing pages further',
    () async {
      final response = await DemoPhotosService.getPhotos();

      expect(response.photos, photos);
      expect(response.total, photos.length);
      expect(response.offset, 0);
      expect(response.limit, greaterThanOrEqualTo(photos.length));
    },
  );

  test('albums only ever point at listed photos', () {
    final albums = DemoPhotosService.albums();
    final relPaths = photos.map((p) => p.relPath).toSet();

    expect(albums, isNotEmpty);
    for (final album in albums) {
      expect(album.id, isNegative, reason: 'a demo id must not collide');
      final items = DemoPhotosService.listAlbumItems(album.id);
      expect(items.length, album.itemCount, reason: album.name);
      for (final item in items) {
        expect(item.albumId, album.id);
        expect(DemoPhotosService.isDemoSerial(item.deviceSerial), isTrue);
        expect(relPaths, contains(item.relPath));
      }
    }
  });

  test('the favorites album mirrors the favorite keys', () {
    final favorites = DemoPhotosService.albums().singleWhere(
      (a) => a.isFavorites,
    );
    final items = DemoPhotosService.listAlbumItems(favorites.id);

    expect(
      items.map((i) => DemoPhotosService.selectionKey(i.relPath)).toSet(),
      DemoPhotosService.favoriteKeys(),
    );
  });

  test(
    'a star moves a photo into Favorites, and taking it off moves it out',
    () async {
      PhotoAlbum favorites() =>
          DemoPhotosService.albums().singleWhere((a) => a.isFavorites);
      Set<String> items() => {
        for (final item in DemoPhotosService.listAlbumItems(favorites().id))
          item.relPath,
      };
      final starred = DemoPhotosService.favoriteKeys();
      final photo = photos.firstWhere(
        (p) => !starred.contains(DemoPhotosService.selectionKey(p.relPath)),
      );
      final before = favorites().itemCount;
      // The stars are static, so a failure midway must not leak into the rest.
      addTearDown(() async {
        final key = DemoPhotosService.selectionKey(photo.relPath);
        if ((await DemoPhotosService.listFavoriteKeys()).contains(key)) {
          await DemoPhotosService.toggleFavorite(relPath: photo.relPath);
        }
      });

      expect(
        await DemoPhotosService.toggleFavorite(relPath: photo.relPath),
        isTrue,
      );
      expect(items(), contains(photo.relPath));
      expect(favorites().itemCount, before + 1);

      expect(
        await DemoPhotosService.toggleFavorite(relPath: photo.relPath),
        isFalse,
      );
      expect(items(), isNot(contains(photo.relPath)));
      expect(favorites().itemCount, before);
    },
  );

  test('an unknown album is empty rather than an error', () {
    expect(DemoPhotosService.listAlbumItems(42), isEmpty);
  });

  group('PhotosController.demo', () {
    test('shows the whole catalog, starred as listed', () async {
      final controller = PhotosController.demo();
      addTearDown(controller.dispose);

      await controller.refresh();

      final shown = controller.photos.where((p) => p.isRemote).toList();
      expect(shown.length, photos.length);
      expect(controller.hasMore, isFalse);
      expect(controller.quarkUnreachable, isFalse);
      expect({
        for (final p in shown)
          if (p.isFavorite) p.id,
      }, DemoPhotosService.favoriteKeys());
      expect(
        controller.albums.map((a) => a.name),
        containsAll(DemoPhotosService.albums().map((a) => a.name)),
      );
      for (final p in shown) {
        expect(
          controller.thumbnailUrl(p.id)!.scheme,
          DemoPhotosService.assetScheme,
        );
      }
    });

    test('starring a sample photo stays local and flips back', () async {
      final controller = PhotosController.demo();
      addTearDown(controller.dispose);
      await controller.refresh();
      final id = controller.photos.firstWhere((p) => !p.isFavorite).id;

      await controller.toggleFavorite(id);
      expect(controller.photos.firstWhere((p) => p.id == id).isFavorite, true);

      await controller.toggleFavorite(id);
      expect(controller.photos.firstWhere((p) => p.id == id).isFavorite, false);
    });

    test('refuses album changes with readable copy', () async {
      final controller = PhotosController.demo();
      addTearDown(controller.dispose);
      await controller.refresh();
      const refusal = Errors.demoModeReadOnly;
      final readable = isA<MessageException>().having(
        (e) => Errors.message(e, 'change the album'),
        'message',
        refusal,
      );

      await expectLater(controller.createAlbum('New'), throwsA(readable));
      await expectLater(controller.renameAlbum(-2, 'X'), throwsA(readable));
      await expectLater(controller.deleteAlbum(-2), throwsA(readable));

      controller.toggleSelection(controller.photos.first.id);
      final outcome = await controller.addSelectedToAlbum(-2);
      expect(outcome.added, 0);
      expect(outcome.failed, 1);
      expect(Errors.message(outcome.error, 'add photos'), refusal);
    });
  });
}
