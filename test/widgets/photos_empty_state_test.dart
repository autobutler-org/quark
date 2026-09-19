import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/photos/photos_empty_state.dart';

/// #2009 and #2042: both empty states were copy only. The library said photos
/// "will appear here" while the only way to put one there was an unlabeled "+"
/// in the corner, and an empty album pointed at a control in the app bar
/// instead of offering the action where the user was already looking.
void main() {
  Future<void> pumpEmptyState(
    WidgetTester tester, {
    String? albumName,
    bool showingFavorites = false,
    VoidCallback? onUploadPhotos,
    VoidCallback? onAddPhotosToAlbum,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhotosEmptyState(
            unreachable: false,
            showingFavorites: showingFavorites,
            albumName: albumName,
            onRetry: () {},
            onManageHosts: () {},
            onUploadPhotos: onUploadPhotos,
            onAddPhotosToAlbum: onAddPhotosToAlbum,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an empty library offers the upload it describes', (
    tester,
  ) async {
    var uploads = 0;
    await pumpEmptyState(tester, onUploadPhotos: () => uploads++);

    await tester.tap(find.byKey(const ValueKey('photos_empty_upload')));
    await tester.pump();

    expect(find.text('Upload photos'), findsOneWidget);
    expect(uploads, 1);
  });

  testWidgets('an empty album offers to add photos to it', (tester) async {
    var adds = 0;
    await pumpEmptyState(
      tester,
      albumName: 'Iceland',
      onAddPhotosToAlbum: () => adds++,
    );

    expect(find.textContaining('Iceland'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('album_empty_add_photos')));
    await tester.pump();

    expect(adds, 1);
  });

  testWidgets('an album that cannot be added to offers nothing', (
    tester,
  ) async {
    await pumpEmptyState(tester, albumName: 'Screenshots');

    expect(find.byKey(const ValueKey('album_empty_add_photos')), findsNothing);
  });

  testWidgets('favorites are earned with a star, not an upload', (
    tester,
  ) async {
    await pumpEmptyState(tester, showingFavorites: true, onUploadPhotos: () {});

    expect(find.text('No favorites yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('photos_empty_upload')), findsNothing);
  });

  testWidgets('a library with no upload handler stays copy only', (
    tester,
  ) async {
    await pumpEmptyState(tester);

    expect(find.byKey(const ValueKey('photos_empty_upload')), findsNothing);
  });
}
