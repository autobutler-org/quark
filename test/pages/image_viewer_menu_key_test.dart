import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/tab_to.dart';

/// #2604: the photo's menu opened on a right-click and from nowhere else, so
/// a keyboard user could not reach it from the photo.
void main() {
  // 64x64 solid PNG — the viewer needs bytes it can actually decode.
  final bytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAT0lEQVR42u3P'
      'QQkAAAgEsIttCIMZywi+hcEKLNXzWgQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE'
      'BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQELgvWNcGlSbHPawAAAABJRU5ErkJg'
      'gg==',
    ),
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpViewer(WidgetTester tester) async {
    // A phone: the menu carries the bar's actions there, so it has entries
    // without a relPath sending metadata requests to the network.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ImageViewerPage(bytes: bytes, name: 'first.jpg'),
      ),
    );
    await tester.runAsync(() async {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    await tester.pumpAndSettle();
  }

  testWidgets('the context-menu key opens the photo menu', (tester) async {
    await pumpViewer(tester);
    expect(find.byType(PopupMenuItem<int>), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();

    expect(find.byType(PopupMenuItem<int>), findsWidgets);
  });

  testWidgets('Shift+F10 opens the same menu', (tester) async {
    await pumpViewer(tester);

    await pressShiftF10(tester);
    await tester.pumpAndSettle();

    expect(find.byType(PopupMenuItem<int>), findsWidgets);
  });
}
