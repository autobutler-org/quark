import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/duplicates_controller.dart';
import 'package:quark/models/duplicate_group.dart';
import 'package:quark/pages/photo_duplicates_page.dart';
import 'package:quark/utils/error_text.dart';

/// #1666: the duplicates page lists groups, asks before deleting, and says
/// when a copy could not be deleted.
void main() {
  const group = DuplicateGroup(
    isExact: true,
    photos: [
      (deviceSerial: '', relPath: 'Camera/beach.jpg'),
      (deviceSerial: '', relPath: 'Backups/beach.jpg'),
    ],
  );

  Future<List<String>> pumpPage(
    WidgetTester tester, {
    List<DuplicateGroup> groups = const [group],
    Object? loadError,
    bool deleteFails = false,
  }) async {
    final deleted = <String>[];
    final controller = DuplicatesController(
      getDuplicates: () async {
        if (loadError != null) throw loadError;
        return deleted.isEmpty ? groups : const [];
      },
      listDevices: () async => const [],
      deleteFile: (rootDir, fileName, {deviceSerial}) async {
        if (deleteFails) throw const ApiException(500);
        deleted.add('$rootDir/$fileName');
      },
      thumbnailUrl: (path, {serial, size}) => Uri.parse('memory:$path'),
    );
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: PhotoDuplicatesPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();
    return deleted;
  }

  testWidgets('offers no format to keep without a picture in several', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.byKey(const ValueKey('duplicates_keep_format')), findsNothing);
  });

  testWidgets('offers no format for two shots that only share a name', (
    tester,
  ) async {
    await pumpPage(
      tester,
      groups: const [
        DuplicateGroup(
          isExact: false,
          maxDistance: 9,
          photos: [
            (deviceSerial: '', relPath: 'Camera/IMG_1.HEIC'),
            (deviceSerial: '', relPath: 'Export/IMG_1.jpg'),
          ],
        ),
      ],
    );

    expect(find.byKey(const ValueKey('duplicates_keep_format')), findsNothing);
  });

  testWidgets('deletes the copy in the format not kept', (tester) async {
    final deleted = await pumpPage(
      tester,
      groups: const [
        DuplicateGroup(
          isExact: false,
          maxDistance: 1,
          photos: [
            (deviceSerial: '', relPath: 'Camera/IMG_1.HEIC'),
            (deviceSerial: '', relPath: 'Export/Beach day.jpg'),
          ],
        ),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('duplicates_keep_format')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('duplicates_keep_format_option_HEIC')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Keep: HEIC'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('duplicates_delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();

    expect(deleted, ['Export/Beach day.jpg']);
  });

  testWidgets('deletes the marked copy after asking', (tester) async {
    final deleted = await pumpPage(tester);

    expect(find.text('Identical copies · 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('duplicates_delete')));
    await tester.pumpAndSettle();
    expect(find.text('Move to Trash?'), findsOneWidget);
    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();

    // The first copy is kept; every other identical copy starts marked.
    expect(deleted, ['Backups/beach.jpg']);
    expect(find.text('No duplicates found'), findsOneWidget);
  });

  testWidgets('says when a copy could not be deleted', (tester) async {
    await pumpPage(tester, deleteFails: true);

    await tester.tap(find.byKey(const ValueKey('duplicates_delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't delete 1 photo."), findsOneWidget);
  });

  testWidgets('words a failed load', (tester) async {
    await pumpPage(tester, loadError: Exception('boom'));

    expect(find.text("Couldn't find duplicate photos."), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
  });
}
