import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/slideshow_controller.dart';
import 'package:quark/models/music_album.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/models/slideshow_photo.dart';

/// A music player that records what it was told.
class _FakeMusic implements SlideshowMusic {
  final log = <String>[];

  @override
  Future<void> play(List<Uri> tracks) async =>
      log.add('play ${tracks.map((t) => t.path).join(',')}');

  @override
  Future<void> pause() async => log.add('pause');

  @override
  Future<void> resume() async => log.add('resume');

  @override
  Future<void> stop() async => log.add('stop');
}

List<SlideshowPhoto> _photos(List<String> names) => [
  for (final name in names)
    SlideshowPhoto(id: name, name: name, relPath: 'Photos/$name'),
];

void main() {
  late List<String> loaded;
  late _FakeMusic music;

  setUp(() {
    loaded = [];
    music = _FakeMusic();
  });

  SlideshowController controller(
    List<String> names, {
    int startIndex = 0,
    Random? random,
    List<MusicAlbum> albums = const [],
    Object? failOn,
  }) => SlideshowController(
    photos: _photos(names),
    startIndex: startIndex,
    random: random,
    loadSlide: (photo) async {
      loaded.add(photo.id);
      if (photo.id == failOn) throw Exception('gone');
      return Uint8List.fromList([photo.id.codeUnitAt(0)]);
    },
    listMusicAlbums: () async => albums,
    listAlbumTracks: (key) async => [
      MusicTrack(relPath: '$key/1.mp3'),
      MusicTrack(relPath: '$key/2.mp3'),
    ],
    trackUrl: (track) => Uri(path: track.relPath),
    music: music,
  );

  testWidgets('plays the photos in the order given, from the start index', (
    tester,
  ) async {
    final c = controller(['a.jpg', 'b.jpg', 'c.jpg'], startIndex: 1)..start();
    await tester.pump();
    expect(c.current?.id, 'b.jpg');
    expect(c.position, 1);

    await tester.pump(const Duration(seconds: 5));
    expect(c.current?.id, 'c.jpg');

    // After the last it starts over.
    await tester.pump(const Duration(seconds: 5));
    expect(c.current?.id, 'a.jpg');
    c.dispose();
  });

  testWidgets('skips videos', (tester) async {
    final c = controller(['a.jpg', 'clip.mp4', 'b.heic'])..start();
    await tester.pump();

    expect(c.count, 2);
    await tester.pump(const Duration(seconds: 5));
    expect(c.current?.id, 'b.heic');
    c.dispose();
  });

  testWidgets('a start index on a video starts on the photo after it', (
    tester,
  ) async {
    final c = controller(['a.jpg', 'clip.mp4', 'b.jpg'], startIndex: 1)
      ..start();
    await tester.pump();

    expect(c.current?.id, 'b.jpg');
    c.dispose();
  });

  testWidgets('preloads the next photo', (tester) async {
    final c = controller(['a.jpg', 'b.jpg', 'c.jpg'])..start();
    await tester.pump();

    expect(loaded, ['a.jpg', 'b.jpg']);
    await tester.pump(const Duration(seconds: 5));
    // b came from the preload: only c is new.
    expect(loaded, ['a.jpg', 'b.jpg', 'c.jpg']);
    c.dispose();
  });

  testWidgets('advances on the chosen interval', (tester) async {
    final c = controller(['a.jpg', 'b.jpg', 'c.jpg'])..start();
    await tester.pump();

    c.setInterval(10);
    await tester.pump(const Duration(seconds: 9));
    expect(c.current?.id, 'a.jpg');
    await tester.pump(const Duration(seconds: 1));
    expect(c.current?.id, 'b.jpg');
    c.dispose();
  });

  testWidgets('paused, it stays put; next and previous still move', (
    tester,
  ) async {
    final c = controller(['a.jpg', 'b.jpg', 'c.jpg'])..start();
    await tester.pump();

    c.togglePlaying();
    expect(c.isPlaying, isFalse);
    await tester.pump(const Duration(seconds: 30));
    expect(c.current?.id, 'a.jpg');

    c.next();
    await tester.pump();
    expect(c.current?.id, 'b.jpg');
    c.previous();
    c.previous();
    await tester.pump();
    expect(c.current?.id, 'c.jpg');

    c.togglePlaying();
    await tester.pump(const Duration(seconds: 5));
    expect(c.current?.id, 'a.jpg');
    c.dispose();
  });

  testWidgets('a manual step restarts the countdown', (tester) async {
    final c = controller(['a.jpg', 'b.jpg', 'c.jpg'])..start();
    await tester.pump();

    await tester.pump(const Duration(seconds: 4));
    c.next();
    await tester.pump(const Duration(seconds: 4));
    expect(c.current?.id, 'b.jpg');
    await tester.pump(const Duration(seconds: 1));
    expect(c.current?.id, 'c.jpg');
    c.dispose();
  });

  testWidgets(
    'shuffle keeps the current photo and plays every photo once a round',
    (tester) async {
      final names = [for (var i = 0; i < 8; i++) '$i.jpg'];
      final c = controller(names, startIndex: 3, random: Random(1))..start();
      await tester.pump();

      c.setShuffle(true);
      expect(c.shuffle, isTrue);
      expect(c.current?.id, '3.jpg');
      expect(c.position, 0);

      final seen = {c.current!.id};
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(seconds: 5));
        seen.add(c.current!.id);
      }
      expect(seen, names.toSet());

      // Off again, the grid's order resumes from the photo showing.
      final showing = c.current!.id;
      c.setShuffle(false);
      expect(c.position, names.indexOf(showing));
      c.dispose();
    },
  );

  testWidgets('a photo that fails to load shows the error, then moves on', (
    tester,
  ) async {
    final c = controller(['a.jpg', 'b.jpg'], failOn: 'a.jpg')..start();
    await tester.pump();

    expect(c.error, isNotNull);
    expect(c.image, isNull);
    await tester.pump(const Duration(seconds: 5));
    expect(c.error, isNull);
    expect(c.current?.id, 'b.jpg');
    c.dispose();
  });

  testWidgets('controls show on activity and hide after a few seconds', (
    tester,
  ) async {
    final c = controller(['a.jpg', 'b.jpg'])..start();
    await tester.pump();

    expect(c.controlsVisible, isTrue);
    await tester.pump(SlideshowController.controlsTimeout);
    expect(c.controlsVisible, isFalse);

    c.showControls();
    expect(c.controlsVisible, isTrue);
    await tester.pump(SlideshowController.controlsTimeout);
    expect(c.controlsVisible, isFalse);
    c.dispose();
  });

  group('music', () {
    testWidgets('an empty library offers none', (tester) async {
      final c = controller(['a.jpg'])..start();
      await tester.pump();

      expect(c.hasMusic, isFalse);
      c.dispose();
    });

    testWidgets("the chosen album's tracks play, and stop with the slideshow", (
      tester,
    ) async {
      final c = controller(
        ['a.jpg', 'b.jpg'],
        albums: const [MusicAlbum(key: 'k1', title: 'Blue')],
      )..start();
      await tester.pump();

      expect(c.hasMusic, isTrue);
      c.chooseMusic('k1');
      await tester.pump();
      expect(c.musicAlbum?.title, 'Blue');
      expect(music.log, ['play k1/1.mp3,k1/2.mp3']);

      c.togglePlaying();
      c.togglePlaying();
      c.dispose();
      await tester.pump();
      expect(music.log, ['play k1/1.mp3,k1/2.mp3', 'pause', 'resume', 'stop']);
    });

    testWidgets('choosing no music stops it', (tester) async {
      final c = controller(
        ['a.jpg'],
        albums: const [MusicAlbum(key: 'k1', title: 'Blue')],
      )..start();
      await tester.pump();

      c.chooseMusic('k1');
      await tester.pump();
      c.chooseMusic(null);
      await tester.pump();

      expect(c.musicAlbum, isNull);
      expect(music.log.last, 'stop');
      c.dispose();
    });
  });

  // testWidgets fails a test that ends with a timer still pending, so this
  // proves dispose cancels the advance and the controls' hide.
  testWidgets('stops advancing once disposed', (tester) async {
    final c = controller(['a.jpg', 'b.jpg'])..start();
    await tester.pump();
    c.dispose();
    await tester.pump();
    expect(c.current?.id, 'a.jpg');
  });
}
