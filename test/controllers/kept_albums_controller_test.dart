import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/kept_albums_controller.dart';
import 'package:quark/models/kept_album.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/photo_disk_cache.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/kept_albums_config.dart';

/// #4222: a kept album downloads its photos, keeps up as they join and leave
/// it, waits for Wi-Fi, and frees its photos when it is no longer kept. Every
/// service is a fake; no test touches the network.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const host = 'https://quark.local';
  const account = 'ada';

  PhotoAlbumItem photo(int albumId, String path) => PhotoAlbumItem(
    id: path.hashCode,
    albumId: albumId,
    deviceSerial: 'sd1',
    relPath: path,
    addedAt: DateTime.utc(2026),
  );

  late Map<int, List<PhotoAlbumItem>> onQuark;
  late Map<(String, KeptRendition), int> kept;
  late List<KeptAlbum> saved;
  late List<String> fetched;
  late bool metered;
  late bool offline;
  late Set<String> noPreview;
  Completer<void>? gate;
  late StreamController<FileEvent> events;
  late StreamController<int> albumChanges;
  late KeptAlbumsController controller;

  Future<Uint8List?> fetch(String kind, String path) async {
    await gate?.future;
    if (offline) throw Exception('network is unreachable');
    if (kind == 'preview' && noPreview.contains(path)) {
      throw ApiException(404, 'no preview');
    }
    fetched.add('$kind $path');
    return Uint8List(kind == 'preview' ? 10 : 100);
  }

  KeptAlbumsController build({List<KeptAlbum> stored = const []}) =>
      KeptAlbumsController(
        load: () async => List.of(stored),
        save: (albums) async => saved = List.of(albums),
        listAlbumItems: (albumId) async {
          if (offline) throw Exception('network is unreachable');
          final items = onQuark[albumId];
          if (items == null) throw ApiException(404, 'no such album');
          return List.of(items);
        },
        fetchPreview: (path, {serial}) => fetch('preview', path),
        fetchPhoto: (path, {serial}) => fetch('photo', path),
        keep:
            (
              path, {
              serial,
              host,
              account,
              required rendition,
              required download,
            }) async {
              final known = kept[(path, rendition)];
              if (known != null) return known;
              final bytes = await download();
              if (bytes == null) return null;
              return kept[(path, rendition)] = bytes.length;
            },
        release: (path, {serial, host, account, required rendition}) async =>
            kept.remove((path, rendition)),
        isMetered: () async => metered,
        events: events.stream,
        albumChanges: albumChanges.stream,
        scope: () => (host: host, account: account),
      );

  setUp(() {
    onQuark = {
      1: [photo(1, 'trip/a.jpg'), photo(1, 'trip/b.jpg')],
    };
    kept = {};
    saved = [];
    fetched = [];
    metered = false;
    offline = false;
    noPreview = {};
    gate = null;
    events = StreamController.broadcast();
    albumChanges = StreamController.broadcast();
    controller = build();
  });

  tearDown(() async {
    controller.dispose();
    await events.close();
    await albumChanges.close();
  });

  Set<String> keptPaths() => {for (final key in kept.keys) key.$1};

  test('keeping an album downloads every preview and saves it', () async {
    await controller.start();
    await controller.keepAlbum(albumId: 1, name: 'Trip');

    expect(kept.keys, {
      ('trip/a.jpg', KeptRendition.preview),
      ('trip/b.jpg', KeptRendition.preview),
    });
    expect(controller.isKept(1), isTrue);
    expect(controller.progressOf(1)!.status, KeptAlbumStatus.ready);
    expect(saved.single.items.map((item) => item.relPath), [
      'trip/a.jpg',
      'trip/b.jpg',
    ]);
    expect(saved.single.keptBytes, 20);
    expect(saved.single.complete, isTrue);
  });

  test('full originals keep the original beside each preview', () async {
    await controller.start();
    await controller.keepAlbum(albumId: 1, name: 'Trip', originals: true);

    expect(kept.length, 4);
    expect(saved.single.keptBytes, 220);
  });

  test('a HEIC keeps its stored preview and never an original', () async {
    onQuark[1] = [photo(1, 'trip/c.heic')];
    await controller.start();
    await controller.keepAlbum(albumId: 1, name: 'Trip', originals: true);

    expect(kept.keys, [('trip/c.heic', KeptRendition.preview)]);
    expect(fetched, ['photo trip/c.heic']);
  });

  test('a photo the Quark renders no preview of keeps its original', () async {
    noPreview.add('trip/a.jpg');
    await controller.start();
    await controller.keepAlbum(albumId: 1, name: 'Trip');

    expect(kept.keys, contains(('trip/a.jpg', KeptRendition.original)));
    expect(saved.single.complete, isTrue);
  });

  testWidgets('a photo added to the album on the Quark is kept on the next '
      'event, and one removed is released', (tester) async {
    await controller.start();
    await controller.keepAlbum(albumId: 1, name: 'Trip');
    expect(keptPaths(), {'trip/a.jpg', 'trip/b.jpg'});

    onQuark[1] = [photo(1, 'trip/b.jpg'), photo(1, 'trip/c.jpg')];
    events.add(const FileEvent(kind: 'upload', path: 'trip/c.jpg'));
    await tester.pump(KeptAlbumsConfig.syncDebounce);
    await tester.pump();

    expect(keptPaths(), {'trip/b.jpg', 'trip/c.jpg'});
  });

  testWidgets('a change this phone made to a kept album syncs it', (
    tester,
  ) async {
    await controller.start();
    await controller.keepAlbum(albumId: 1, name: 'Trip');

    onQuark[1] = [photo(1, 'trip/a.jpg')];
    albumChanges.add(1);
    await tester.pump(KeptAlbumsConfig.syncDebounce);
    await tester.pump();

    expect(keptPaths(), {'trip/a.jpg'});
  });

  test(
    'a photo another kept album holds stays when one album lets it go',
    () async {
      onQuark[2] = [photo(2, 'trip/a.jpg')];
      await controller.start();
      await controller.keepAlbum(albumId: 1, name: 'Trip');
      await controller.keepAlbum(albumId: 2, name: 'Best');

      await controller.stopKeeping(1);

      expect(keptPaths(), {'trip/a.jpg'});
      expect(controller.isKept(1), isFalse);
      expect(saved.map((album) => album.albumId), [2]);
    },
  );

  test('stopping keeping an album mid-download stops it and frees what it '
      'kept', () async {
    await controller.start();
    gate = Completer();
    final keeping = controller.keepAlbum(albumId: 1, name: 'Trip');
    await pumpEventQueue();

    await controller.stopKeeping(1);
    gate!.complete();
    await keeping;

    expect(kept, isEmpty);
    expect(fetched, ['preview trip/a.jpg']);
    expect(controller.isKept(1), isFalse);
  });

  test('stopping keeping an album frees its photos', () async {
    await controller.start();
    await controller.keepAlbum(albumId: 1, name: 'Trip', originals: true);

    await controller.stopKeeping(1);

    expect(kept, isEmpty);
    expect(saved, isEmpty);
    expect(controller.progressOf(1), isNull);
  });

  test('on mobile data it waits, unless the album allows it', () async {
    metered = true;
    await controller.start();
    await controller.keepAlbum(albumId: 1, name: 'Trip');

    expect(kept, isEmpty);
    expect(controller.progressOf(1)!.status, KeptAlbumStatus.waitingForWifi);

    await controller.keepAlbum(albumId: 3, name: 'Other');
    onQuark[4] = [photo(4, 'x/y.jpg')];
    await controller.keepAlbum(
      albumId: 4,
      name: 'Anywhere',
      allowMobileData: true,
    );
    expect(keptPaths(), {'x/y.jpg'});
  });

  test(
    'a keep cut off by a dropped connection resumes after a restart',
    () async {
      await controller.start();
      offline = true;
      await controller.keepAlbum(albumId: 1, name: 'Trip');
      expect(kept, isEmpty);
      expect(controller.progressOf(1)!.status, KeptAlbumStatus.failed);

      controller.dispose();
      offline = false;
      controller = build(stored: saved);
      await controller.start();

      expect(keptPaths(), {'trip/a.jpg', 'trip/b.jpg'});
      expect(controller.progressOf(1)!.status, KeptAlbumStatus.ready);
    },
  );

  test('a photo already kept is not downloaded again', () async {
    await controller.start();
    await controller.keepAlbum(albumId: 1, name: 'Trip');
    fetched.clear();

    await controller.sync();

    expect(fetched, isEmpty);
  });

  test('an album deleted on the Quark stops being kept', () async {
    await controller.start();
    await controller.keepAlbum(albumId: 1, name: 'Trip');
    onQuark.remove(1);

    await controller.sync();

    expect(controller.isKept(1), isFalse);
    expect(kept, isEmpty);
  });

  test("another account's kept albums neither list nor sync", () async {
    controller.dispose();
    controller = build(
      stored: const [
        KeptAlbum(albumId: 1, name: 'Trip', host: host, account: 'grace'),
      ],
    );
    await controller.start();

    expect(controller.albums, isEmpty);
    expect(kept, isEmpty);
  });
}
