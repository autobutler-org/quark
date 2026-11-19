import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/slideshow_controller.dart';
import 'package:quark/models/music_album.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/models/slideshow_photo.dart';
import 'package:quark/pages/slideshow_page.dart';

/// A 1x1 transparent PNG.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _SilentMusic implements SlideshowMusic {
  final log = <String>[];
  @override
  Future<void> play(List<Uri> tracks) async => log.add('play');
  @override
  Future<void> pause() async => log.add('pause');
  @override
  Future<void> resume() async => log.add('resume');
  @override
  Future<void> stop() async => log.add('stop');
}

void main() {
  late List<bool> screenOn;
  late _SilentMusic music;

  setUp(() {
    screenOn = [];
    music = _SilentMusic();
  });

  SlideshowController controller({List<MusicAlbum> albums = const []}) =>
      SlideshowController(
        photos: const [
          SlideshowPhoto(id: 'a', name: 'a.jpg', relPath: 'a.jpg'),
          SlideshowPhoto(id: 'b', name: 'b.jpg', relPath: 'b.jpg'),
        ],
        loadSlide: (_) async => _png,
        listMusicAlbums: () async => albums,
        listAlbumTracks: (_) async => const [MusicTrack(relPath: 'song.mp3')],
        trackUrl: (track) => Uri(path: track.relPath),
        music: music,
      );

  /// Pumps a page with a button that opens the slideshow, and opens it.
  Future<void> open(WidgetTester tester, SlideshowController c) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      SlideshowPage(controller: c, keepScreenOn: screenOn.add),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Escape returns to where it was opened and lets the screen '
      'sleep', (tester) async {
    await open(tester, controller());

    expect(find.byKey(const ValueKey('slideshow_view')), findsOneWidget);
    expect(screenOn, [true]);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('slideshow_view')), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    expect(screenOn, [true, false]);
  });

  testWidgets('Exit closes it too', (tester) async {
    await open(tester, controller());

    await tester.tap(find.byKey(const ValueKey('slideshow_exit')));
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('arrow keys step and space pauses', (tester) async {
    await open(tester, controller());
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.byTooltip('Play'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('no music on the Quark hides the music button', (tester) async {
    await open(tester, controller());

    expect(find.byKey(const ValueKey('slideshow_music')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('the album picked plays, and stops when the slideshow ends', (
    tester,
  ) async {
    await open(
      tester,
      controller(
        albums: const [MusicAlbum(key: 'k1', title: 'Blue')],
      ),
    );

    await tester.tap(find.byKey(const ValueKey('slideshow_music')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slideshow_music_option_k1')));
    await tester.pumpAndSettle();
    expect(music.log, ['play']);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(music.log, ['play', 'stop']);
  });
}
