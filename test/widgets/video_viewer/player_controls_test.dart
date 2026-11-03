import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/video_viewer/player_controls.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../support/fake_video_player_platform.dart';
import '../../support/tap_target_guidelines.dart';

/// #3938: every transport button has a name, and play and mute follow state.
void main() {
  VideoPlayerController? controller;

  setUp(() {
    VideoPlayerPlatform.instance = FakeVideoPlayerPlatform(
      duration: const Duration(minutes: 1),
    );
  });

  Future<void> pumpControls(
    WidgetTester tester, {
    bool isFullscreen = false,
  }) async {
    setViewport(tester, wideViewport);
    controller ??= VideoPlayerController.networkUrl(
      Uri.parse('https://quark.local/clip.mp4'),
    );
    if (!controller!.value.isInitialized) {
      await tester.runAsync(controller!.initialize);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PlayerControls(
              controller: controller!,
              isFullscreen: isFullscreen,
              onToggleFullscreen: () {},
              onInteraction: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  tearDown(() async {
    await controller?.dispose();
    controller = null;
  });

  testWidgets('meets the labeled tap target guideline', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpControls(tester);
    try {
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      handle.dispose();
    }
  });

  testWidgets('play, pause and mute names follow the state they act on', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpControls(tester);
    try {
      expect(
        tester.getSemantics(find.byTooltip('Play (Space)')),
        isSemantics(tooltip: 'Play (Space)'),
      );
      expect(
        tester.getSemantics(find.byTooltip('Mute')),
        isSemantics(tooltip: 'Mute'),
      );

      await tester.tap(find.byTooltip('Play (Space)'));
      await tester.pump();
      expect(
        tester.getSemantics(find.byTooltip('Pause (Space)')),
        isSemantics(tooltip: 'Pause (Space)'),
      );
      expect(find.byTooltip('Play (Space)'), findsNothing);

      await tester.tap(find.byTooltip('Mute'));
      await tester.pump();
      expect(
        tester.getSemantics(find.byTooltip('Unmute')),
        isSemantics(tooltip: 'Unmute'),
      );
      expect(find.byTooltip('Mute'), findsNothing);
    } finally {
      // play() starts a position timer. Pause cancels it before the test ends.
      await controller?.pause();
      handle.dispose();
    }
  });

  testWidgets('fullscreen names the direction it will go', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpControls(tester);
    try {
      expect(
        tester.getSemantics(find.byTooltip('Full screen')),
        isSemantics(tooltip: 'Full screen'),
      );

      await pumpControls(tester, isFullscreen: true);
      expect(
        tester.getSemantics(find.byTooltip('Exit full screen')),
        isSemantics(tooltip: 'Exit full screen'),
      );
      expect(find.byTooltip('Full screen'), findsNothing);
    } finally {
      handle.dispose();
    }
  });
}
