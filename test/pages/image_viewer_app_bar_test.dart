import 'package:flutter/gestures.dart';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/widgets/image_viewer/metadata_drawer.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

/// #1709: the app bar carried a close button plus eight more icons, so on a
/// phone the close X sat on top of the prev chevron. Narrow layouts now fold
/// the secondary actions into the more menu, and since #4235 put favorite and
/// info in a row under a full-screen photo.
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
    setViewport(tester, size);
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

  // #4235: a phone shows the photo full screen, with its name in the bar and
  // its actions in a row under it.
  testWidgets('a phone bar keeps only close, the title and more', (
    tester,
  ) async {
    await pumpViewer(tester, phoneSize);

    expect(find.byIcon(QuarkIcons.close), findsOneWidget);
    expect(find.byIcon(QuarkIcons.more_vert), findsOneWidget);
    expect(find.text('first.jpg'), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);

    // A swipe turns the page, so the chevrons are gone.
    expect(find.byIcon(QuarkIcons.chevron_left), findsNothing);
    expect(find.byIcon(QuarkIcons.chevron_right), findsNothing);
    expect(find.byIcon(QuarkIcons.rotate_90_degrees_cw_outlined), findsNothing);
    expect(find.byIcon(QuarkIcons.keyboard_outlined), findsNothing);
    expect(find.byType(IconButton), findsNWidgets(2));

    // relPath is null, so the row under the photo offers Info alone.
    expect(find.byKey(const ValueKey('photo_viewer_action_info')), findsOne);
    expect(
      find.byKey(const ValueKey('photo_viewer_action_share')),
      findsNothing,
    );
  });

  testWidgets('the phone more menu carries rotate', (tester) async {
    await pumpViewer(tester, phoneSize);

    await tester.tap(find.byIcon(QuarkIcons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Rotate 90° CW'), findsOneWidget);
    // Favorite and info live in the row under the photo.
    expect(find.text('Favorite'), findsNothing);
    expect(find.text('Show info'), findsNothing);
    // relPath is null, so the server-side actions stay out.
    expect(find.text('Download'), findsNothing);
    expect(find.text('Delete photo'), findsNothing);
  });

  group('at a narrow viewport (#4235)', () {
    const narrowViewport = Size(360, 640);

    testWidgets('the photo opens tall, with no sheet until Info', (
      tester,
    ) async {
      await pumpViewer(tester, narrowViewport);
      await tester.pumpAndSettle();

      // The space the photo is fitted into; the test image never decodes.
      expect(
        tester.getSize(find.byKey(const ValueKey('image_viewer_photo'))).height,
        greaterThan(280),
      );
      expect(find.byType(MetadataDrawer), findsNothing);
      expect(find.byType(DraggableScrollableSheet), findsNothing);

      await tester.tap(find.byKey(const ValueKey('photo_viewer_action_info')));
      await tester.pumpAndSettle();

      expect(find.byType(MetadataDrawer), findsOneWidget);
      // No metadata, so the sheet says what the viewer knows.
      expect(find.text('No metadata available'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(MetadataDrawer),
          matching: find.text('first.jpg'),
        ),
        findsOneWidget,
      );

      // Info again, or a tap on the photo, closes it.
      await tester.tap(find.byKey(const ValueKey('photo_viewer_action_info')));
      await tester.pumpAndSettle();
      expect(find.byType(MetadataDrawer), findsNothing);
    });

    testWidgets('i toggles the sheet', (tester) async {
      await pumpViewer(tester, narrowViewport);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pumpAndSettle();
      expect(find.byType(MetadataDrawer), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pumpAndSettle();
      expect(find.byType(MetadataDrawer), findsNothing);
    });

    testWidgets('the sheet starts closed even when the sidebar was open', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'photo_viewer_sidebar_open': true,
      });
      await pumpViewer(tester, narrowViewport);
      await tester.pumpAndSettle();

      expect(find.byType(MetadataDrawer), findsNothing);
    });
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
