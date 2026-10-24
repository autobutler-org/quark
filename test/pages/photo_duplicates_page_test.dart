import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/duplicates_controller.dart';
import 'package:quark/controllers/photo_index_controller.dart';
import 'package:quark/models/duplicate_group.dart';
import 'package:quark/pages/photo_duplicates_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/photo_index_service.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/thumbnail_cache_config.dart';

import '../support/fake_thumbnail_store.dart';
import '../support/tap_target_guidelines.dart' show setViewport;

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
    Size size = const Size(390, 844),
    double textScale = 1,
    PhotoIndexController? indexController,
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
    setViewport(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: PhotoDuplicatesPage(
            controller: controller,
            indexController: indexController,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return deleted;
  }

  testWidgets('opens with nothing selected and no delete bar', (tester) async {
    await pumpPage(
      tester,
      groups: const [
        DuplicateGroup(
          isExact: true,
          photos: [
            (deviceSerial: '', relPath: 'Camera/beach.jpg'),
            (deviceSerial: '', relPath: 'Backups/beach.jpg'),
            (deviceSerial: '', relPath: 'beach copy.jpg'),
          ],
        ),
        DuplicateGroup(
          isExact: true,
          photos: [
            (deviceSerial: '', relPath: 'Camera/cat.jpg'),
            (deviceSerial: '', relPath: 'cat copy.jpg'),
          ],
        ),
      ],
    );

    expect(find.text('Identical copies · 3'), findsOneWidget);
    expect(find.text('Identical copies · 2'), findsOneWidget);
    expect(find.text('Keep'), findsNWidgets(5));
    expect(find.text('Delete'), findsNothing);
    expect(find.textContaining(RegExp(r'Delete \d+ photo')), findsNothing);
    expect(find.byKey(const ValueKey('duplicates_delete')), findsNothing);
  });

  testWidgets('the delete bar counts the copies the user selected', (
    tester,
  ) async {
    await pumpPage(
      tester,
      groups: const [
        DuplicateGroup(
          isExact: true,
          photos: [
            (deviceSerial: '', relPath: 'Camera/beach.jpg'),
            (deviceSerial: '', relPath: 'Backups/beach.jpg'),
            (deviceSerial: '', relPath: 'beach copy.jpg'),
          ],
        ),
        DuplicateGroup(
          isExact: true,
          photos: [
            (deviceSerial: '', relPath: 'Camera/cat.jpg'),
            (deviceSerial: '', relPath: 'cat copy.jpg'),
          ],
        ),
      ],
    );

    for (final id in const [
      ':Backups/beach.jpg',
      ':beach copy.jpg',
      ':cat copy.jpg',
    ]) {
      // The bar appears with the first mark and takes room from the list,
      // which may push a later tile out of view.
      final tile = find.byKey(ValueKey('duplicate_photo_$id'));
      await tester.ensureVisible(tile);
      await tester.pump();
      await tester.tap(tile);
      await tester.pump();
    }

    expect(find.text('Delete'), findsNWidgets(3));
    expect(find.text('Keep'), findsNWidgets(2));
    // Two groups are on screen. The bar counts the three marked copies.
    expect(find.text('Delete 3 photos'), findsOneWidget);
    expect(find.text('Delete 2 photos'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('duplicates_delete')));
    await tester.pumpAndSettle();
    expect(find.text('Move 3 photos to Trash?'), findsOneWidget);
  });

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

  Finder tile(String id) => find.byKey(ValueKey('duplicate_photo_$id'));

  testWidgets('deletes the marked copy after asking', (tester) async {
    final deleted = await pumpPage(tester);

    expect(find.text('Identical copies · 2'), findsOneWidget);
    expect(find.textContaining(RegExp(r'Delete \d+ photo')), findsNothing);
    await tester.tap(tile(':Backups/beach.jpg'));
    await tester.pump();
    expect(find.text('Delete 1 photo'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('duplicates_delete')));
    await tester.pumpAndSettle();
    expect(find.text('Move 1 photo to Trash?'), findsOneWidget);
    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();

    expect(deleted, ['Backups/beach.jpg']);
    expect(find.text('No duplicates found'), findsOneWidget);
  });

  testWidgets('says when a copy could not be deleted', (tester) async {
    await pumpPage(tester, deleteFails: true);

    await tester.tap(tile(':Backups/beach.jpg'));
    await tester.pump();
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

  /// #3362's library: four identical groups, one of them three copies, so
  /// the suggestion marks five copies across four groups, and one similar
  /// pair.
  const library = [
    DuplicateGroup(
      isExact: true,
      photos: [
        (deviceSerial: '', relPath: 'Camera/a.jpg'),
        (deviceSerial: '', relPath: 'Backups/a.jpg'),
        (deviceSerial: '', relPath: 'Old/a.jpg'),
      ],
    ),
    DuplicateGroup(
      isExact: true,
      photos: [
        (deviceSerial: '', relPath: 'Camera/b.jpg'),
        (deviceSerial: '', relPath: 'Backups/b.jpg'),
      ],
    ),
    DuplicateGroup(
      isExact: true,
      photos: [
        (deviceSerial: '', relPath: 'Camera/c.jpg'),
        (deviceSerial: '', relPath: 'Backups/c.jpg'),
      ],
    ),
    DuplicateGroup(
      isExact: true,
      photos: [
        (deviceSerial: '', relPath: 'Camera/d.jpg'),
        (deviceSerial: 'USB1', relPath: 'Backups/d.jpg'),
      ],
    ),
    DuplicateGroup(
      isExact: false,
      maxDistance: 9,
      photos: [
        (deviceSerial: '', relPath: 'Camera/dog.jpg'),
        (deviceSerial: '', relPath: 'Edits/dog.jpg'),
      ],
    ),
  ];

  // #3362: a copy marked Delete and a red delete bar were on screen before
  // the user chose anything, one tap from a bulk delete on a phone.
  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    testWidgets('opens with no copy marked and no delete bar at $size', (
      tester,
    ) async {
      await pumpPage(tester, groups: library, size: size);

      expect(find.text('Delete'), findsNothing);
      expect(find.byKey(const ValueKey('duplicates_delete')), findsNothing);
      expect(
        find.byKey(const ValueKey('duplicates_select_suggested')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the bar appears with the first mark and goes with the last', (
    tester,
  ) async {
    await pumpPage(tester, groups: library);

    await tester.tap(tile(':Backups/b.jpg'));
    await tester.pump();
    expect(find.text('Delete 1 photo'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget, reason: 'one tile marked');

    // The bar takes room from the list, which may push the tile below it.
    await tester.ensureVisible(tile(':Backups/b.jpg'));
    await tester.pump();
    await tester.tap(tile(':Backups/b.jpg'));
    await tester.pump();
    expect(find.byKey(const ValueKey('duplicates_delete')), findsNothing);
  });

  testWidgets('clearing the marks takes the bar away', (tester) async {
    await pumpPage(tester, groups: library);
    await tester.tap(find.byKey(const ValueKey('duplicates_select_suggested')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('duplicates_clear_selection')));
    await tester.pump();

    expect(find.text('Delete'), findsNothing);
    expect(find.byKey(const ValueKey('duplicates_delete')), findsNothing);
  });

  testWidgets('the bar counts the marked copies and the groups they are in, '
      'and the confirmation lists every one', (tester) async {
    final deleted = await pumpPage(tester, groups: library);

    await tester.tap(find.byKey(const ValueKey('duplicates_select_suggested')));
    await tester.pump();

    const marked = [
      ':Backups/a.jpg',
      ':Old/a.jpg',
      ':Backups/b.jpg',
      ':Backups/c.jpg',
      'USB1:Backups/d.jpg',
    ];
    expect(find.text('Delete 5 photos'), findsOneWidget);
    expect(find.text('5 copies in 4 groups'), findsOneWidget);
    // The similar pair is never suggested.
    expect(
      find.byKey(const ValueKey('duplicates_select_suggested')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('duplicates_delete')));
    await tester.pumpAndSettle();

    expect(find.text('Move 5 photos to Trash?'), findsOneWidget);
    for (final id in marked) {
      expect(
        find.byKey(ValueKey('duplicate_delete_item_$id')),
        findsOneWidget,
        reason: '$id is not listed',
      );
    }
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(
              'duplicate_delete_item_',
            ),
      ),
      findsNWidgets(marked.length),
    );

    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();
    expect(deleted, [
      'Backups/a.jpg',
      'Old/a.jpg',
      'Backups/b.jpg',
      'Backups/c.jpg',
      'Backups/d.jpg',
    ]);
  });

  testWidgets('canceling the confirmation deletes nothing', (tester) async {
    final deleted = await pumpPage(tester, groups: library);
    await tester.tap(tile(':Old/a.jpg'));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('duplicates_delete')));
    await tester.pumpAndSettle();
    expect(find.text('Move 1 photo to Trash?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(deleted, isEmpty);
    expect(find.text('Delete 1 photo'), findsOneWidget);
  });

  // #2575: each copy reads where it is in plain words, never the Quark's
  // storage path, at either width and at double text size.
  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    for (final textScale in const [1.0, 2.0]) {
      testWidgets('names each copy by place without its storage path at $size '
          'and ${textScale}x text', (tester) async {
        await pumpPage(
          tester,
          size: size,
          textScale: textScale,
          groups: const [
            DuplicateGroup(
              isExact: true,
              photos: [
                (
                  deviceSerial: '',
                  relPath: 'users/ux-test/photos/dup-copy-1.jpg',
                ),
                (
                  deviceSerial: '',
                  relPath: 'users/ux-test/photos/Trips/dup-copy-2.jpg',
                ),
              ],
            ),
          ],
        );

        expect(tester.takeException(), isNull);
        expect(find.text('dup-copy-1.jpg'), findsOneWidget);
        expect(find.text('Photos'), findsOneWidget);
        expect(find.text('Photos › Trips'), findsOneWidget);
        expect(find.textContaining('users/'), findsNothing);
      });
    }
  }

  // #3362: some Keep thumbnails stayed grey. The page drew each copy with a
  // bare URL, so a thumbnail the Quark refused while busy, or one it lacked,
  // was never asked for again.
  testWidgets('every Keep and Delete tile ends on its thumbnail, in identical '
      'and similar groups alike', (tester) async {
    final png = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xFF3366CC), BlendMode.src);
      final image = await recorder.endRecording().toImage(8, 8);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return bytes!.buffer.asUint8List();
    }))!;
    final previous = ThumbnailCacheManager.instance;
    // Every thumbnail's first fetch answers 503, the way a Quark does while
    // its IO is saturated: a page of duplicates asks for every copy at once.
    final refused = <String>{};
    ThumbnailCacheManager.instance = FakeThumbnailStore((url) {
      if (refused.add(url)) {
        throw HttpExceptionWithStatus(503, 'busy', uri: Uri.parse(url));
      }
      return png;
    });
    addTearDown(() => ThumbnailCacheManager.instance = previous);
    imageCache
      ..clear()
      ..clearLiveImages();
    addTearDown(
      () => imageCache
        ..clear()
        ..clearLiveImages(),
    );

    await pumpPage(
      tester,
      size: const Size(1280, 800),
      groups: const [
        group,
        DuplicateGroup(
          isExact: false,
          maxDistance: 9,
          photos: [
            (deviceSerial: '', relPath: 'Camera/dog.jpg'),
            (deviceSerial: 'USB1', relPath: 'Edits/dog.jpg'),
          ],
        ),
      ],
    );
    await tester.tap(tile(':Backups/beach.jpg'));
    await tester.tap(tile('USB1:Edits/dog.jpg'));

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    await settle();
    await tester.pump(ThumbnailCacheConfig.busyRetryDelay);
    await settle();

    for (final id in const [
      ':Camera/beach.jpg',
      ':Backups/beach.jpg',
      ':Camera/dog.jpg',
      'USB1:Edits/dog.jpg',
    ]) {
      final raw = find.descendant(
        of: tile(id),
        matching: find.byType(RawImage),
      );
      expect(raw, findsOneWidget, reason: '$id has no image');
      expect(
        tester.widget<RawImage>(raw).image,
        isNotNull,
        reason: '$id is still on its placeholder',
      );
    }
    expect(find.text('Delete'), findsNWidgets(2));
    expect(find.text('Keep'), findsNWidgets(2));
  });

  /// #3556: an admin sees whether the index behind these results is
  /// complete; anyone else has no way to know, and sees nothing.
  PhotoIndexController indexController(List<String> fetched) =>
      PhotoIndexController(
        fetch: () async {
          fetched.add('fetch');
          return const PhotoIndexStatus(
            total: 5000,
            hashed: 1200,
            datesRead: 1100,
            failed: 0,
            failures: [],
            running: true,
            paused: false,
          );
        },
        events: const Stream.empty(),
      );

  testWidgets('an admin is told results may be incomplete', (tester) async {
    AppSettings.instance.isAdmin.value = true;
    addTearDown(() => AppSettings.instance.isAdmin.value = false);
    final fetched = <String>[];
    final index = indexController(fetched);
    addTearDown(index.dispose);
    await pumpPage(tester, indexController: index);

    expect(fetched, ['fetch']);
    expect(
      find.text('Still indexing, so results may be incomplete'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('photo_index_pause')), findsOneWidget);
    expect(find.text('Identical copies · 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a non-admin sees nothing and nothing is fetched', (
    tester,
  ) async {
    AppSettings.instance.isAdmin.value = false;
    final fetched = <String>[];
    final index = indexController(fetched);
    addTearDown(index.dispose);
    await pumpPage(tester, indexController: index);

    expect(fetched, isEmpty);
    expect(find.byKey(const ValueKey('photo_index_status')), findsNothing);
    expect(find.text('Identical copies · 2'), findsOneWidget);
  });
}
