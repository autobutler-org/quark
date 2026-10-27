import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/audio_player_page.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/file_viewer_actions.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../support/fake_video_player_platform.dart';

/// A platform whose position moves a tenth of a second on every poll, as a
/// playing song's does.
class _AdvancingPlatform extends FakeVideoPlayerPlatform {
  Duration _position = Duration.zero;

  @override
  Future<Duration> getPosition(int playerId) async =>
      _position += const Duration(milliseconds: 100);
}

/// #2002, audio side: opened straight from its URL on web, the page called
/// play() with no user gesture behind it. The browser rejected it, the
/// controller went erroneous, and the play button did nothing from then on.
void main() {
  final url = Uri.parse('http://quark.test/api/v0/files/download?token=t');

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(MaterialApp(home: page));
    // Bounded pumps: the progress bar animates, so pumpAndSettle never ends.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('without a user gesture, stays paused and playable', (
    tester,
  ) async {
    final platform = FakeVideoPlayerPlatform(rejectPlay: true);
    VideoPlayerPlatform.instance = platform;

    await pumpPage(
      tester,
      AudioPlayerPage(url: url, name: 'song.mp3', canAutoplay: () => false),
    );

    expect(platform.playCalls, 0);

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump(const Duration(milliseconds: 50));
    expect(platform.playCalls, 1);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('after a user gesture, starts playing', (tester) async {
    final platform = FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;

    await pumpPage(
      tester,
      AudioPlayerPage(url: url, name: 'song.mp3', canAutoplay: () => true),
    );

    expect(platform.playCalls, 1);

    await tester.pumpWidget(const SizedBox());
  });

  // #3728: Download says it downloaded, as the other viewers do (#3160).
  testWidgets('Download reports the saved file', (tester) async {
    VideoPlayerPlatform.instance = FakeVideoPlayerPlatform();
    final saves = <(String, String?, String?)>[];
    saveViewedFile = (path, {serial, fileName}) async {
      saves.add((path, serial, fileName));
      return '/home/me/$fileName';
    };
    addTearDown(() => saveViewedFile = FilesService.saveFile);

    await pumpPage(
      tester,
      AudioPlayerPage(
        url: Uri.http('quark.test', '/api/v0/files/download', {
          'filePath': 'Music/song.mp3',
          'serial': 'USB1',
        }),
        name: 'song.mp3',
        canAutoplay: () => false,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('audio_player_download')));
    await tester.pump();
    await tester.pump();

    expect(saves, [('Music/song.mp3', 'USB1', 'song.mp3')]);
    expect(find.text('Downloaded song.mp3'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  // #3284: the 10-second song counts once its first 5 seconds are heard,
  // and only once however long it keeps playing.
  testWidgets('counts one play once half a short song is heard', (
    tester,
  ) async {
    VideoPlayerPlatform.instance = _AdvancingPlatform();
    final plays = <String>[];
    await pumpPage(
      tester,
      AudioPlayerPage(
        url: Uri.parse(
          'http://quark.test/api/v0/files/download?filePath=m%2Fsong.mp3&serial=USB1',
        ),
        name: 'song.mp3',
        canAutoplay: () => true,
        recordPlay: (relPath, {serial = ''}) async =>
            plays.add('$serial:$relPath'),
      ),
    );

    expect(plays, isEmpty);
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(plays, ['USB1:m/song.mp3']);

    await tester.pumpWidget(const SizedBox());
  });
}
