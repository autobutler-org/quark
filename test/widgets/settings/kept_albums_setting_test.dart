import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/kept_albums_controller.dart';
import 'package:quark/models/kept_album.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/widgets/settings/kept_albums_setting.dart';

import '../../support/tap_target_guidelines.dart' show setViewport;

/// #4222: Settings lists the albums kept on this phone with the space each
/// takes, and removing one frees it.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);

  late Set<String> kept;
  late StreamController<FileEvent> events;
  late StreamController<int> albumChanges;

  KeptAlbumsController build(List<KeptAlbum> stored) => KeptAlbumsController(
    load: () async => stored,
    save: (_) async {},
    listAlbumItems: (albumId) async => [
      PhotoAlbumItem(
        id: 1,
        albumId: albumId,
        deviceSerial: 'sd1',
        relPath: 'trip/a.jpg',
        addedAt: DateTime.utc(2026),
      ),
    ],
    fetchPreview: (path, {serial}) async => Uint8List(3 * 1024 * 1024),
    fetchPhoto: (path, {serial}) async => Uint8List(0),
    keep:
        (
          path, {
          serial,
          host,
          account,
          required rendition,
          required download,
        }) async {
          kept.add(path);
          return (await download())?.length;
        },
    release: (path, {serial, host, account, required rendition}) async =>
        kept.remove(path),
    isMetered: () async => false,
    events: events.stream,
    albumChanges: albumChanges.stream,
    scope: () => (host: 'https://quark.local', account: 'ada'),
  );

  setUp(() {
    kept = {};
    events = StreamController.broadcast();
    albumChanges = StreamController.broadcast();
  });

  tearDown(() async {
    await events.close();
    await albumChanges.close();
  });

  Future<KeptAlbumsController> pump(
    WidgetTester tester,
    Size size,
    List<KeptAlbum> stored,
  ) async {
    setViewport(tester, size);
    final controller = build(stored);
    addTearDown(controller.dispose);
    await controller.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: KeptAlbumsSetting(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  const trip = KeptAlbum(
    albumId: 7,
    name: 'A summer trip with a name too long for one line',
    host: 'https://quark.local',
    account: 'ada',
  );

  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';

    testWidgets('a kept album shows its size and state ($label)', (
      tester,
    ) async {
      await pump(tester, size, const [trip]);

      expect(tester.takeException(), isNull);
      expect(find.text('Previews · 3.0 MB · Ready offline'), findsOneWidget);
    });

    testWidgets('with none kept it says how to keep one ($label)', (
      tester,
    ) async {
      await pump(tester, size, const []);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('No albums are kept'), findsOneWidget);
    });
  }

  testWidgets('remove stops keeping the album and frees its photos', (
    tester,
  ) async {
    final controller = await pump(tester, wideViewport, const [trip]);
    expect(kept, {'trip/a.jpg'});

    await tester.tap(
      find.byKey(const ValueKey('settings_kept_album_remove_7')),
    );
    await tester.pumpAndSettle();

    expect(controller.isKept(7), isFalse);
    expect(kept, isEmpty);
    expect(find.byKey(const ValueKey('settings_kept_album_7')), findsNothing);
  });
}
