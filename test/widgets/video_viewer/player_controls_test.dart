import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/video_viewer/player_controls.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../support/fake_video_player_platform.dart';

/// #2603: every transport button was a bare icon, so a screen reader
/// announced five unnamed buttons in a row.
void main() {
  Future<VideoPlayerController> pumpControls(
    WidgetTester tester, {
    bool isFullscreen = false,
  }) async {
    VideoPlayerPlatform.instance = FakeVideoPlayerPlatform();
    final controller = VideoPlayerController.networkUrl(
      Uri.parse('http://quark.test/video.mp4'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PlayerControls(
              controller: controller,
              isFullscreen: isFullscreen,
              onToggleFullscreen: () {},
              onInteraction: () {},
            ),
          ),
        ),
      ),
    );
    await controller.initialize();
    await tester.pump();
    return controller;
  }

  testWidgets('names every control for a screen reader', (tester) async {
    await pumpControls(tester);

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    for (final tooltip in [
      'Play',
      'Back 10 seconds',
      'Forward 10 seconds',
      'Mute',
      'Playback speed',
      'Fullscreen',
    ]) {
      expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the names follow the state they toggle', (tester) async {
    final controller = await pumpControls(tester, isFullscreen: true);
    await controller.setVolume(0);
    await controller.play();
    await tester.pump();

    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byTooltip('Unmute'), findsOneWidget);
    expect(find.byTooltip('Exit fullscreen'), findsOneWidget);
    await controller.pause();
    await tester.pumpWidget(const SizedBox());
  });
}
