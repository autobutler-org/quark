import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/audio_player_page.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../support/fake_video_player_platform.dart';

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
}
