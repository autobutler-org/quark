import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/playback_position.dart';
import 'package:quark/pages/video_viewer_page.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../support/fake_video_player_platform.dart';

/// A fake player that records where it was told to seek.
class _SeekRecordingPlatform extends FakeVideoPlayerPlatform {
  final seeks = <Duration>[];

  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      seeks.add(position);
}

/// #2002: a video opened straight from its URL on web showed its first frame
/// and then buffered forever. The page called play() with no user gesture
/// behind it, the browser rejected it, and the controller went erroneous:
/// the progress bar spun indeterminately and play did nothing.
void main() {
  final url = Uri.parse('http://quark.test/api/v0/files/download?token=t');

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(MaterialApp(home: page));
    // Bounded pumps: the progress bar animates, so pumpAndSettle never ends.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  final indeterminateBar = find.byWidgetPredicate(
    (w) => w is LinearProgressIndicator && w.value == null,
  );

  testWidgets('without a user gesture, stays paused and playable', (
    tester,
  ) async {
    final platform = FakeVideoPlayerPlatform(rejectPlay: true);
    VideoPlayerPlatform.instance = platform;

    await pumpPage(
      tester,
      VideoViewerPage(url: url, name: 'clip.mp4', canAutoplay: () => false),
    );

    expect(platform.playCalls, 0);
    expect(indeterminateBar, findsNothing);

    await tester.tap(find.byIcon(QuarkIcons.play_arrow));
    await tester.pump(const Duration(milliseconds: 50));
    expect(platform.playCalls, 1);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('after a user gesture, starts playing', (tester) async {
    final platform = FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;

    await pumpPage(
      tester,
      VideoViewerPage(url: url, name: 'clip.mp4', canAutoplay: () => true),
    );

    expect(platform.playCalls, 1);
    expect(indeterminateBar, findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  final fileUrl = Uri.http('quark.test', '/api/v0/files/download', {
    'filePath': 'Movies/clip.mp4',
    'serial': 'USB1',
  });

  Future<PlaybackPosition> noSave(
    String relPath, {
    String? serial,
    required Duration position,
    required Duration duration,
  }) async => const PlaybackPosition();

  testWidgets('opening a video with a stored position seeks there', (
    tester,
  ) async {
    final platform = _SeekRecordingPlatform();
    VideoPlayerPlatform.instance = platform;
    final loaded = <(String, String?)>[];

    await pumpPage(
      tester,
      VideoViewerPage(
        url: fileUrl,
        name: 'clip.mp4',
        canAutoplay: () => true,
        loadPlayback: (relPath, {serial}) async {
          loaded.add((relPath, serial));
          return const PlaybackPosition(
            position: Duration(seconds: 4),
            duration: Duration(seconds: 10),
          );
        },
        savePlayback: noSave,
        setPlaybackWatched: (relPath, {serial, required watched}) async =>
            PlaybackPosition(watched: watched),
      ),
    );

    expect(loaded, [('Movies/clip.mp4', 'USB1')]);
    expect(platform.seeks, [const Duration(seconds: 4)]);
    expect(platform.playCalls, 1);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a watched video offers Mark as unwatched, which calls through', (
    tester,
  ) async {
    final platform = _SeekRecordingPlatform();
    VideoPlayerPlatform.instance = platform;
    final watchedCalls = <bool>[];

    await pumpPage(
      tester,
      VideoViewerPage(
        url: fileUrl,
        name: 'clip.mp4',
        canAutoplay: () => false,
        loadPlayback: (relPath, {serial}) async => const PlaybackPosition(
          position: Duration(seconds: 4),
          duration: Duration(seconds: 10),
          watched: true,
        ),
        savePlayback: noSave,
        setPlaybackWatched: (relPath, {serial, required watched}) async {
          watchedCalls.add(watched);
          return PlaybackPosition(watched: watched);
        },
      ),
    );

    expect(platform.seeks, isEmpty, reason: 'a watched video starts over');

    await tester.tap(find.byKey(const ValueKey('video_viewer_more')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Mark as unwatched'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('video_viewer_mark_unwatched')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(watchedCalls, [false]);

    await tester.tap(find.byKey(const ValueKey('video_viewer_more')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.byKey(const ValueKey('video_viewer_mark_watched')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a URL that names no file has no watched item and no calls', (
    tester,
  ) async {
    VideoPlayerPlatform.instance = FakeVideoPlayerPlatform();
    var calls = 0;

    await pumpPage(
      tester,
      VideoViewerPage(
        url: url,
        name: 'clip.mp4',
        canAutoplay: () => false,
        loadPlayback: (relPath, {serial}) async {
          calls++;
          return const PlaybackPosition();
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('video_viewer_more')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Save Frame'), findsOneWidget);
    expect(find.text('Mark as watched'), findsNothing);
    expect(calls, 0);

    await tester.pumpWidget(const SizedBox());
  });
}
