import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_list_column.dart';
import 'package:quark/models/photo_sort.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secure_storage.dart';

/// The choices made on this device, each kept in shared preferences: each has
/// to survive a restart, start at its default, and fall back to the default
/// when what is stored is not something it knows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(mockSecureStorage);

  final settings = AppSettings.instance;

  Future<void> loadWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    await settings.load();
  }

  for (final (name, read, byDefault, persisted, unknown, change, stored)
      in <
        (
          String,
          Object Function(),
          Object,
          (Map<String, Object>, Object),
          Map<String, Object>?,
          (Future<void> Function(), Object),
          Map<String, Object>,
        )
      >[
        // #2510: A-Z, the order the sidebar showed before it had a sort.
        (
          'album sort',
          () => settings.albumSort.value,
          AlbumSort.nameAsc,
          ({'albumSort': 'oldest'}, AlbumSort.oldest),
          {'albumSort': 'garbage'},
          (() => settings.setAlbumSort(AlbumSort.newest), AlbumSort.newest),
          {'albumSort': 'newest'},
        ),
        // #2509, #2592: newest taken first.
        (
          'photo sort',
          () => (settings.photoSortField.value, settings.photoSortOrder.value),
          (PhotoSortField.taken, PhotoSortOrder.desc),
          (
            {'photoSortField': 'name', 'photoSortOrder': 'asc'},
            (PhotoSortField.name, PhotoSortOrder.asc),
          ),
          {'photoSortField': 'garbage', 'photoSortOrder': 'garbage'},
          (
            () =>
                settings.setPhotoSort(PhotoSortField.name, PhotoSortOrder.asc),
            (PhotoSortField.name, PhotoSortOrder.asc),
          ),
          {'photoSortField': 'name', 'photoSortOrder': 'asc'},
        ),
        // #1565, #1566: Modified and Size.
        (
          'Files list columns',
          () => settings.fileListColumns.value,
          {FileListColumn.modified, FileListColumn.size},
          (
            {
              'fileListColumns': <String>['kind', 'device'],
            },
            {FileListColumn.kind, FileListColumn.device},
          ),
          {
            'fileListColumns': <String>['kind', 'garbage'],
          },
          (
            () async {
              await settings.setFileListColumnVisible(
                FileListColumn.kind,
                true,
              );
              await settings.setFileListColumnVisible(
                FileListColumn.size,
                false,
              );
            },
            {FileListColumn.kind, FileListColumn.modified},
          ),
          {
            'fileListColumns': unorderedEquals(['kind', 'modified']),
          },
        ),
        // #1746: off, so nobody sees sample content they never asked for.
        (
          'demo mode',
          () => settings.demoMode.value,
          false,
          ({'demoMode': true}, true),
          null,
          (() => settings.setDemoMode(true), true),
          {'demoMode': true},
        ),
      ]) {
    group(name, () {
      test('is the default until changed', () async {
        await loadWith({});

        expect(read(), byDefault);
      });

      test('reads a persisted choice on load', () async {
        await loadWith(persisted.$1);

        expect(read(), persisted.$2);
      });

      if (unknown != null) {
        test(
          'an unrecognized persisted value falls back to the default',
          () async {
            await loadWith(unknown);

            expect(read(), byDefault);
          },
        );
      }

      test('changing it publishes and persists the choice', () async {
        await loadWith({});

        await change.$1();

        expect(read(), change.$2);
        final prefs = await SharedPreferences.getInstance();
        for (final MapEntry(:key, :value) in stored.entries) {
          expect(prefs.get(key), value, reason: key);
        }
        await settings.load();
        expect(read(), change.$2, reason: 'after a restart');
      });
    });
  }

  test(
    'photo sort keeps an explicit date-added choice made before #2592',
    () async {
      await loadWith({'photoSortField': 'added', 'photoSortOrder': 'desc'});

      expect(settings.photoSortField.value, PhotoSortField.added);
    },
  );

  test(
    'Files list columns keeps a choice of no optional columns at all',
    () async {
      await loadWith({'fileListColumns': <String>[]});

      expect(settings.fileListColumns.value, isEmpty);
    },
  );

  test('switching demo mode off again clears the persisted flag', () async {
    await loadWith({'demoMode': true});

    await settings.setDemoMode(false);

    expect(settings.demoMode.value, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('demoMode'), isFalse);
  });
}
