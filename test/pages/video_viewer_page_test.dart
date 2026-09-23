import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/video_viewer_page.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../support/fake_video_player_platform.dart';

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
}
