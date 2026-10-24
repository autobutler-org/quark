import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/widgets/photos/add_to_album_sheet.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart' show setViewport;

PhotoAlbum _album(int id, String name) => PhotoAlbum(
  id: id,
  name: name,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  itemCount: 1,
);

/// #3361: the add-to-album sheet opened with every album unchecked, so an
/// album the photo was already in offered to add it again, and the page never
/// heard that an album had changed.
void main() {
  for (final (name, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('checks the albums the photo is in, and a tap on one takes '
        'it out ($name)', (tester) async {
      setViewport(tester, size);
      final calls = <String>[];
      var changes = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
          home: Scaffold(
            body: AddToAlbumSheetHost(
              deviceSerial: 'sd1',
              relPath: 'camera/1.jpg',
              onChanged: () => changes++,
              listAlbums: ({bool tree = false}) async => [
                _album(1, 'Trips'),
                _album(2, 'Pets'),
              ],
              loadMemberAlbumIds: (relPath, {String? serial}) async {
                calls.add('members($relPath, $serial)');
                return {1};
              },
              addPhotoToAlbum:
                  (albumId, {required deviceSerial, required relPath}) async {
                    calls.add('add($albumId)');
                    return true;
                  },
              removePhotoFromAlbum:
                  (albumId, {required deviceSerial, required relPath}) async =>
                      calls.add('remove($albumId)'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Finder checked(int id) => find.descendant(
        of: find.byKey(ValueKey('add_to_album_$id')),
        matching: find.byIcon(QuarkIcons.check_circle_rounded),
      );
      expect(calls, ['members(camera/1.jpg, sd1)']);
      expect(checked(1), findsOneWidget);
      expect(checked(2), findsNothing);

      await tester.tap(find.byKey(const ValueKey('add_to_album_1')));
      await tester.pumpAndSettle();

      expect(calls.last, 'remove(1)');
      expect(checked(1), findsNothing);
      expect(changes, 1);
    });
  }

  testWidgets('without its memberships the sheet still lists the albums', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddToAlbumSheetHost(
            deviceSerial: '',
            relPath: 'camera/1.jpg',
            listAlbums: ({bool tree = false}) async => [_album(1, 'Trips')],
            loadMemberAlbumIds: (relPath, {String? serial}) async =>
                throw Exception('offline'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('add_to_album_1')), findsOneWidget);
  });
}
