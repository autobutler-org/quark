import 'package:flutter/gestures.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #1709: the app bar carried a close button plus eight more icons, so on a
/// phone the close X sat on top of the prev chevron. Narrow layouts now fold
/// the secondary actions into the more menu.
void main() {
  // 64x64 solid PNG — the viewer needs real bytes to decode.
  final bytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAT0lEQVR42u3P'
      'QQkAAAgEsIttCIMZywi+hcEKLNXzWgQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE'
      'BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQELgvWNcGlSbHPawAAAABJRU5ErkJg'
      'gg==',
    ),
  );

  const phoneSize = Size(390, 844);
  const desktopSize = Size(1400, 900);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Pumps the viewer on photo 1 of 3. `relPath` stays null so no metadata
  /// fetch is attempted.
  Future<void> pumpViewer(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ImageViewerPage(
          bytes: bytes,
          name: 'first.jpg',
          initialIndex: 0,
          imageCount: 3,
          onLoadImage: (index) async => (bytes, 'photo$index.jpg', null, null),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a phone bar keeps only close, the chevrons and more', (
    tester,
  ) async {
    await pumpViewer(tester, phoneSize);

    expect(find.byIcon(QuarkIcons.close), findsOneWidget);
    expect(find.byIcon(QuarkIcons.chevron_left), findsOneWidget);
    expect(find.byIcon(QuarkIcons.chevron_right), findsOneWidget);
    expect(find.byIcon(QuarkIcons.more_vert), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);

    // Everything else moved into the menu.
    expect(find.byIcon(QuarkIcons.star_border), findsNothing);
    expect(find.byIcon(QuarkIcons.rotate_90_degrees_cw_outlined), findsNothing);
    expect(find.byIcon(QuarkIcons.info_outline), findsNothing);
    expect(find.byIcon(QuarkIcons.keyboard_outlined), findsNothing);

    // Five hit targets on a 390px bar leaves the close button room to breathe.
    expect(find.byType(IconButton), findsNWidgets(4)); // + the popup button
  });

  testWidgets('the phone more menu carries the collapsed actions', (
    tester,
  ) async {
    await pumpViewer(tester, phoneSize);

    await tester.tap(find.byIcon(QuarkIcons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Favorite'), findsOneWidget);
    expect(find.text('Rotate 90° CW'), findsOneWidget);
    // The sidebar starts open, so the menu offers to hide it.
    expect(find.text('Hide info'), findsOneWidget);
    // relPath is null, so the server-side actions stay out.
    expect(find.text('Download'), findsNothing);
    expect(find.text('Delete photo'), findsNothing);
  });

  testWidgets('the phone menu toggles the info sidebar', (tester) async {
    await pumpViewer(tester, phoneSize);

    await tester.tap(find.byIcon(QuarkIcons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Hide info'), findsOneWidget);

    await tester.tap(find.text('Hide info'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(QuarkIcons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Show info'), findsOneWidget);
  });

  testWidgets('a wide bar still shows every action inline', (tester) async {
    await pumpViewer(tester, desktopSize);

    expect(find.byIcon(QuarkIcons.close), findsOneWidget);
    expect(find.byIcon(QuarkIcons.chevron_left), findsOneWidget);
    expect(find.byIcon(QuarkIcons.chevron_right), findsOneWidget);
    expect(find.byIcon(QuarkIcons.star_border), findsOneWidget);
    expect(
      find.byIcon(QuarkIcons.rotate_90_degrees_cw_outlined),
      findsOneWidget,
    );
    expect(find.byIcon(QuarkIcons.info), findsOneWidget);
    expect(find.byIcon(QuarkIcons.keyboard_outlined), findsOneWidget);
    // No relPath, so no more menu on desktop.
    expect(find.byIcon(QuarkIcons.more_vert), findsNothing);
  });

  group('right-click on the photo (#2276)', () {
    List<String> entries(WidgetTester tester) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(PopupMenuItem<int>),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data!)
        .toList();

    testWidgets('opens the More options menu at the pointer', (tester) async {
      await pumpViewer(tester, phoneSize);
      await tester.tap(find.byIcon(QuarkIcons.more_vert));
      await tester.pumpAndSettle();
      final fromButton = entries(tester);
      await tester.tapAt(const Offset(5, 400));
      await tester.pumpAndSettle();

      final photo = tester.getCenter(
        find.byKey(const ValueKey('image_viewer_photo')),
      );
      await tester.tapAt(photo, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(entries(tester), fromButton);
      expect(fromButton, contains('Rotate 90° CW'));
      expect(
        tester.getTopLeft(find.byType(PopupMenuItem<int>).first).dy,
        closeTo(photo.dy, 40),
      );
    });

    testWidgets('opens nothing when the menu would be empty', (tester) async {
      // Wide, the bar shows favorite, rotate and info as buttons, and a
      // device photo has no server actions, so there is no menu.
      await pumpViewer(tester, desktopSize);

      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('image_viewer_photo'))),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuItem<int>), findsNothing);
      expect(find.byIcon(QuarkIcons.more_vert), findsNothing);
    });
  });
}
