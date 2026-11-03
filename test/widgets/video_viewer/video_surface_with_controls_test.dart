import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/video_viewer/video_surface_with_controls.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../support/fake_video_player_platform.dart';

/// #2003: Space plays and pauses, ← and → skip back and forward.
void main() {
  late VideoPlayerController controller;

  setUp(() {
    VideoPlayerPlatform.instance = FakeVideoPlayerPlatform(
      duration: const Duration(minutes: 1),
    );
  });

  Future<void> pumpSurface(WidgetTester tester) async {
    controller = VideoPlayerController.networkUrl(
      Uri.parse('https://quark.local/clip.mp4'),
    );
    await tester.runAsync(controller.initialize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoSurfaceWithControls(
            controller: controller,
            isFullscreen: false,
            onToggleFullscreen: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  tearDown(() async => controller.dispose());

  testWidgets('Space toggles playback', (tester) async {
    await pumpSurface(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(controller.value.isPlaying, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(controller.value.isPlaying, isFalse);
  });

  testWidgets('arrows skip ten seconds and stop at the ends', (tester) async {
    await pumpSurface(tester);
    await tester.runAsync(() => controller.seekTo(const Duration(seconds: 25)));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(controller.value.position, const Duration(seconds: 35));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(controller.value.position, const Duration(seconds: 15));

    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.pump();
    expect(controller.value.position, Duration.zero);
  });
}
