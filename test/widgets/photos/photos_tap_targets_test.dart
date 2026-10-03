import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/photo_sort.dart';
import 'package:quark/widgets/photos/photo_sort_button.dart';
import 'package:quark/widgets/photos/photos_empty_state.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart';

/// #2603, #2605: the Photos page's app widgets — the sort button and its menu,
/// and every empty state's buttons — are labeled 48dp targets.
void main() {
  Future<void> pump(WidgetTester tester, Size size, Widget child) async {
    setViewport(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: Scaffold(
          body: Center(
            child: Padding(padding: const EdgeInsets.all(8), child: child),
          ),
        ),
      ),
    );
  }

  for (final size in const [narrowViewport, wideViewport]) {
    testWidgets('the sort button and its menu at $size', (tester) async {
      await pump(
        tester,
        size,
        PhotoSortButton(
          sortField: PhotoSortField.taken,
          sortOrder: PhotoSortOrder.desc,
          onChanged: (_, _) {},
        ),
      );
      await expectTapTargetGuidelines(tester);
      await tester.tap(find.byType(PhotoSortButton));
      await tester.pumpAndSettle();
      await expectTapTargetGuidelines(tester);
    });

    for (final (label, state) in [
      (
        'an unreachable Quark',
        PhotosEmptyState(
          unreachable: true,
          showingFavorites: false,
          hostAddress: 'quark.lan',
          onRetry: () {},
          onManageHosts: () {},
        ),
      ),
      (
        'an empty library',
        PhotosEmptyState(
          unreachable: false,
          showingFavorites: false,
          onRetry: () {},
          onManageHosts: () {},
          onUploadPhotos: () {},
        ),
      ),
      (
        'an empty album',
        PhotosEmptyState(
          unreachable: false,
          showingFavorites: false,
          albumName: 'Trips',
          onRetry: () {},
          onManageHosts: () {},
          onAddPhotosToAlbum: () {},
        ),
      ),
    ]) {
      testWidgets('$label at $size', (tester) async {
        await pump(tester, size, state);
        await expectTapTargetGuidelines(tester);
      });
    }
  }
}
