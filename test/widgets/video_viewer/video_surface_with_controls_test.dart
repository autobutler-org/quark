import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/image_viewer/shortcut_row.dart';
import 'package:quark/widgets/video_viewer/video_surface_with_controls.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../support/fake_video_player_platform.dart';

/// #2003: Space plays and pauses, ← and → skip back and forward.
/// #3938: each control announces its name, shortcut included, and ? lists them.
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

  testWidgets('names each control, shortcut included', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpSurface(tester);
    try {
      void expectName(String name) {
        expect(
          tester.getSemantics(find.byTooltip(name)),
          isSemantics(tooltip: name),
          reason: '$name is the accessible name',
        );
      }

      expectName('Play (Space)');
      expectName('Back 10 seconds (←)');
      expectName('Forward 10 seconds (→)');
      expectName('Mute');
      expectName('Playback speed');
      expectName('Full screen');
      expect(find.bySemanticsLabel('Playback position'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expectName('Pause (Space)');

      await tester.tap(find.byTooltip('Mute'));
      await tester.pump();
      expectName('Unmute');
    } finally {
      // play() starts a position timer. Pause cancels it before the test ends.
      await controller.pause();
      handle.dispose();
    }
  });

  testWidgets('? lists the shortcuts this player handles', (tester) async {
    await pumpSurface(tester);

    // Shift+/ is "?" on a US keyboard. The simulator has no physical "?" key.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('video_shortcuts_dialog')),
      findsOneWidget,
    );
    expect(find.byType(ShortcutRow), findsNWidgets(4));
    expect(find.text('Play / Pause'), findsOneWidget);
    expect(find.text('Back 10 seconds'), findsOneWidget);
    expect(find.text('Forward 10 seconds'), findsOneWidget);
    expect(find.text('Show this help'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video_shortcuts_dialog')), findsNothing);
  });
}
