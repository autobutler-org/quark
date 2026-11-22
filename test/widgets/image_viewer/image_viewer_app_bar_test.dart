import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/image_viewer/image_viewer_app_bar.dart';
import 'package:quark/widgets/image_viewer/image_viewer_more_menu.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/tap_target_guidelines.dart' show setViewport;

/// Share in the photo viewer's more menu (#1911): offered for a photo on the
/// Quark at any width, and never for a photo from the device.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<List<String>> pumpBar(
    WidgetTester tester, {
    required bool isDesktop,
    String? relPath,
    int imageCount = 1,
    DateTime? date,
  }) async {
    final events = <String>[];
    setViewport(
      tester,
      isDesktop ? const Size(1400, 900) : const Size(390, 844),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: ImageViewerAppBar(
            isDesktop: isDesktop,
            name: 'beach.jpg',
            date: date,
            currentIndex: 2,
            imageCount: imageCount,
            hasPrev: false,
            hasNext: false,
            onPrevious: () {},
            onNext: () {},
            isFavorite: false,
            sidebarOpen: false,
            relPath: relPath,
            onClose: () {},
            onToggleFavorite: () {},
            onRotate: () {},
            onDownload: () {},
            onToggleSidebar: () {},
            onShowShortcuts: () {},
            moreMenu: ImageViewerMoreMenu(
              includeBarActions: !isDesktop,
              relPath: relPath,
              sourceAlbum: null,
              onRotate: () {},
              onDownload: () {},
              onAddToAlbum: () {},
              onRemoveFromAlbum: () {},
              onCopy: () {},
              copyUnavailableReason: null,
              onDuplicate: () {},
              onShare: () => events.add('share'),
              onDelete: () {},
            ),
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

  // #4235: a phone's bar is close, the name over "3 of 12 · Nov 10", and More.
  testWidgets('a phone titles the photo and drops the chevrons', (
    tester,
  ) async {
    await pumpBar(
      tester,
      isDesktop: false,
      relPath: 'Photos/beach.jpg',
      imageCount: 12,
      date: DateTime(2025, 11, 10),
    );

    expect(find.text('beach.jpg'), findsOneWidget);
    expect(find.text('3 of 12 · Nov 10'), findsOneWidget);
    expect(find.byKey(const ValueKey('image_viewer_close')), findsOneWidget);
    expect(find.byKey(const ValueKey('image_viewer_more')), findsOneWidget);
    expect(find.byKey(const ValueKey('image_viewer_previous')), findsNothing);
    expect(find.byKey(const ValueKey('image_viewer_next')), findsNothing);
  });

  testWidgets('a phone leaves out what it does not know', (tester) async {
    await pumpBar(tester, isDesktop: false);

    expect(find.text('beach.jpg'), findsOneWidget);
    expect(find.byKey(const ValueKey('image_viewer_subtitle')), findsNothing);
  });

  testWidgets('a wide bar keeps its counter and chevrons', (tester) async {
    await pumpBar(tester, isDesktop: true, imageCount: 12);

    expect(find.text('3 / 12'), findsOneWidget);
    expect(find.byKey(const ValueKey('image_viewer_previous')), findsOneWidget);
    expect(find.text('beach.jpg'), findsNothing);
  });
}
