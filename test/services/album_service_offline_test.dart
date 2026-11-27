import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/models/kept_album.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/services/album_service.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/kept_albums_store.dart';
import 'package:quark/utils/error_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_quark_http.dart';
import '../support/secure_storage.dart';

/// #4222: with no connection, an album kept on this phone still lists, and
/// still opens, from what its last sync saved. Nothing else does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  useFakeQuark();

  final settings = AppSettings.instance;
  final item = PhotoAlbumItem(
    id: 1,
    albumId: 7,
    deviceSerial: 'sd1',
    relPath: 'trip/a.jpg',
    addedAt: DateTime.utc(2026),
  );

  void goOffline() => answerWith(
    (request) => throw http.ClientException('network is unreachable'),
  );

  setUpAll(() => mockSecureStorage({}));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await settings.load();
    await settings.addHost(
      HostEntry(name: 'Home', hostAddress: 'https://quark.local'),
    );
    await settings.setUsername('ada');
    await settings.setSessionToken('token');
    await KeptAlbumsStore.save([
      KeptAlbum(
        albumId: 7,
        name: 'Trip',
        host: settings.activeHost!,
        account: 'ada',
        items: [item],
      ),
      KeptAlbum(
        albumId: 8,
        name: 'Hers',
        host: settings.activeHost!,
        account: 'grace',
        items: [item],
      ),
    ]);
  });

  test('offline, the kept albums list, and only this account\'s', () async {
    goOffline();

    final albums = await AlbumService.listAlbums(tree: true);

    expect(albums.map((album) => (album.id, album.name, album.itemCount)), [
      (7, 'Trip', 1),
    ]);
  });

  test('offline, a kept album opens with the photos its sync saved', () async {
    goOffline();

    final items = await AlbumService.listAlbumItems(7);

    expect(items.map((item) => item.relPath), ['trip/a.jpg']);
  });

  tearDown(() => KeptAlbumsStore.loaded = const []);

  test('offline with nothing kept, the album list fails with the connection '
      'error, without waiting on storage', () async {
    KeptAlbumsStore.loaded = const [];
    goOffline();

    await expectLater(
      AlbumService.listAlbums(tree: true),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('offline, an album that is not kept still fails', () async {
    goOffline();

    await expectLater(
      AlbumService.listAlbumItems(9),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('a refusal from the Quark is not hidden behind the kept copy', () async {
    answer(403, {'error': 'forbidden'});

    await expectLater(
      AlbumService.listAlbumItems(7),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    "adding a photo to an album announces it, for a kept album's sync",
    () async {
      answer(201, {});
      final changed = AlbumService.changes.first;

      await AlbumService.addPhotoToAlbum(
        7,
        deviceSerial: 'sd1',
        relPath: 'trip/b.jpg',
      );

      expect(await changed, 7);
    },
  );
}
