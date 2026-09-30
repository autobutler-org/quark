import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/video_frame_capture.dart';
import 'package:video_player/video_player.dart';

void main() {
  group('videoFrameFileName', () {
    test('names the frame after the video and where it was taken', () {
      expect(
        videoFrameFileName('clip.mp4', const Duration(milliseconds: 2500)),
        'clip_frame_0m02s.png',
      );
      expect(
        videoFrameFileName('trip.final.MOV', const Duration(seconds: 3725)),
        'trip.final_frame_1h02m05s.png',
      );
    });

    test('keeps a name with no extension whole', () {
      expect(videoFrameFileName('clip', Duration.zero), 'clip_frame_0m00s.png');
    });
  });

  group('captureVideoFrame', () {
    Future<ui.Image> capture(
      WidgetTester tester,
      VideoPlayerController controller,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Center(
          child: RepaintBoundary(
            key: key,
            child: const SizedBox(
              width: 40,
              height: 30,
              child: ColoredBox(color: Color(0xFF3366CC)),
            ),
          ),
        ),
      );
      final bytes = await tester.runAsync(
        () => captureVideoFrame(controller, key),
      );
      final codec = await tester.runAsync(
        () => ui.instantiateImageCodec(bytes!),
      );
      final frame = await tester.runAsync(() => codec!.getNextFrame());
      return frame!.image;
    }

    testWidgets('grabs the frame at the video\'s own resolution', (
      tester,
    ) async {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse('https://quark.local/clip.mp4'),
      );
      controller.value = const VideoPlayerValue(
        duration: Duration(seconds: 3),
        size: Size(80, 60),
      );

      final image = await capture(tester, controller);

      expect((image.width, image.height), (80, 60));
    });

    testWidgets('falls back to the size on screen before the video has one', (
      tester,
    ) async {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse('https://quark.local/clip.mp4'),
      );

      final image = await capture(tester, controller);

      expect((image.width, image.height), (40, 30));
    });
  });
}
