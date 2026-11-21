import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #3428: videos sit in the Photos grid beside photos, so swiping through the
/// viewer reaches them in grid order. A video's page offers to play it and
/// never downloads its bytes as a photo.
void main() {
  // 64x64 solid PNG.
  final bytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAT0lEQVR42u3P'
      'QQkAAAgEsIttCIMZywi+hcEKLNXzWgQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE'
      'BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQELgvWNcGlSbHPawAAAABJRU5ErkJg'
      'gg==',
    ),
  );
  final clip = Uri.parse('https://quark.local/api/v0/files/media?p=clip.mp4');

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a step onto a video shows its play card and loads no photo', (
    tester,
  ) async {
    final loaded = <int>[];
    final played = <(Uri, String)>[];
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: ImageViewerPage(
            bytes: bytes,
            name: 'first.jpg',
            imageCount: 3,
            onLoadImage: (index) async {
              loaded.add(index);
              return (bytes, '$index.jpg', null, null);
            },
            videoAt: (index) =>
                index == 1 ? (url: clip, name: 'clip.mp4') : null,
            playVideo: (context, url, name) async => played.add((url, name)),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(loaded, isEmpty);
    expect(
      find.byKey(const ValueKey('image_viewer_video_play')),
      findsOneWidget,
    );
    expect(find.text('clip.mp4'), findsWidgets);
    // Rotating, favoriting and the photo's menu are a photo's.
    expect(find.byTooltip('Rotate'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('image_viewer_video_play')));
    await tester.pumpAndSettle();
    expect(played, [(clip, 'clip.mp4')]);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(loaded, [2]);
    expect(find.byKey(const ValueKey('image_viewer_video_play')), findsNothing);
  });
}
