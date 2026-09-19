import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/image_viewer/image_viewer_app_bar.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Share in the photo viewer's more menu (#1911): offered for a photo on the
/// Quark at any width, and never for a photo from the device.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<List<String>> pumpBar(
    WidgetTester tester, {
    required bool isDesktop,
    String? relPath,
  }) async {
    final events = <String>[];
    tester.view.physicalSize = isDesktop
        ? const Size(1400, 900)
        : const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: ImageViewerAppBar(
            isDesktop: isDesktop,
            currentIndex: 0,
            imageCount: 1,
            hasPrev: false,
            hasNext: false,
            onPrevious: () {},
            onNext: () {},
            isFavorite: false,
            sidebarOpen: false,
            relPath: relPath,
            sourceAlbum: null,
            onClose: () {},
            onToggleFavorite: () {},
            onRotate: () {},
            onDownload: () {},
            onToggleSidebar: () {},
            onAddToAlbum: () {},
            onRemoveFromAlbum: () {},
            onMakeACopy: () {},
            onShare: () => events.add('share'),
            onDelete: () {},
            onShowShortcuts: () {},
          ),
        ),
      ),
    );
    return events;
  }

  for (final isDesktop in [false, true]) {
    testWidgets(
      'a Quark photo can be shared (${isDesktop ? 'wide' : 'narrow'})',
      (tester) async {
        final events = await pumpBar(
          tester,
          isDesktop: isDesktop,
          relPath: 'Photos/beach.jpg',
        );

        await tester.tap(find.byIcon(QuarkIcons.more_vert));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Share…'));
        await tester.pumpAndSettle();

        expect(events, ['share']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a photo from the device has no Share', (tester) async {
    await pumpBar(tester, isDesktop: false);

    await tester.tap(find.byIcon(QuarkIcons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Share…'), findsNothing);
  });
}
