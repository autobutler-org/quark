import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/widgets/image_viewer/metadata_drawer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

/// #3364: a RenderFlex overflow showed up in the console on a phone, from a
/// layout squeezed during a transition. Every frame of opening the viewer,
/// hiding and showing the info sheet, dragging it and closing the viewer is
/// laid out at both phone sizes here, and any overflow fails the test.
void main() {
  final bytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAT0lEQVR42u3P'
      'QQkAAAgEsIttCIMZywi+hcEKLNXzWgQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE'
      'BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQELgvWNcGlSbHPawAAAABJRU5ErkJg'
      'gg==',
    ),
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Pumps frame by frame for [duration], so a transition's in-between
  /// sizes are laid out rather than skipped.
  Future<void> pumpFrames(WidgetTester tester, Duration duration) async {
    for (var t = Duration.zero; t < duration; t += kFrame) {
      await tester.pump(kFrame);
    }
  }

  for (final size in const [Size(412, 915), Size(360, 640)]) {
    testWidgets('no overflow at ${size.width.toInt()}x${size.height.toInt()}', (
      tester,
    ) async {
      setViewport(tester, size);

      final overflows = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        final text = details.exceptionAsString();
        if (text.contains('overflowed')) {
          overflows.add(text);
        } else {
          previous?.call(details);
        }
      };
      addTearDown(() => FlutterError.onError = previous);

      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('host')),
        ),
      );
      navigatorKey.currentState!.push(
        MaterialPageRoute<bool>(
          builder: (_) => ImageViewerPage(
            bytes: bytes,
            name: 'first.jpg',
            initialIndex: 1,
            imageCount: 3,
            onLoadImage: (index) async => (bytes, 'next.jpg', null, null),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump();
      });
      await pumpFrames(tester, const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.byType(MetadataDrawer), findsOneWidget);

      // Hide the info sheet and show it again.
      for (var i = 0; i < 2; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
        await pumpFrames(tester, const Duration(milliseconds: 400));
      }
      expect(find.byType(MetadataDrawer), findsOneWidget);

      // Drag the sheet down to its smallest and up to its largest.
      final handle = find.byKey(const ValueKey('photo_info_handle'));
      for (final dy in [size.height, -size.height]) {
        final gesture = await tester.startGesture(tester.getCenter(handle));
        for (var i = 0; i < 20; i++) {
          await gesture.moveBy(Offset(0, dy / 20));
          await tester.pump(kFrame);
        }
        await gesture.up();
        await pumpFrames(tester, const Duration(milliseconds: 400));
      }

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester, const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('host'), findsOneWidget);

      expect(overflows, isEmpty);
    });
  }
}

const kFrame = Duration(milliseconds: 16);
