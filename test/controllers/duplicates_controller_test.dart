import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/duplicates_controller.dart';
import 'package:quark/models/duplicate_group.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/duplicates_config.dart';
import 'package:quark/utils/error_text.dart';

StorageDevice _device(String serial, String name) => StorageDevice(
  name: name,
  devicePath: '/dev/$serial',
  mountPoint: '/mnt/$serial',
  fileSystem: 'ext4',
  totalBytes: 1,
  usedBytes: 0,
  availableBytes: 1,
  isInternal: false,
  isEnabled: true,
  serial: serial,
);

/// A Quark with one identical group spanning a USB drive and one similar
/// group, recording every delete.
class _FakeQuark {
  List<DuplicateGroup> groups = const [
    DuplicateGroup(
      isExact: true,
      photos: [
        (deviceSerial: '', relPath: 'Camera/beach.jpg'),
        (deviceSerial: 'USB1', relPath: 'Backups/beach.jpg'),
        (deviceSerial: '', relPath: 'beach copy.jpg'),
      ],
    ),
    DuplicateGroup(
      isExact: false,
      photos: [
        (deviceSerial: '', relPath: 'Camera/dog.jpg'),
        (deviceSerial: '', relPath: 'Edits/dog.jpg'),
      ],
    ),
  ];
  Object? loadError;
  final Set<String> failingDeletes = {};
  final List<String> calls = [];

  DuplicatesController controller() => DuplicatesController(
    getDuplicates: () async {
      calls.add('load');
      final error = loadError;
      if (error != null) throw error;
      return groups;
    },
    listDevices: () async => [_device('USB1', 'Backup drive')],
    deleteFile: (rootDir, fileName, {deviceSerial}) async {
      if (failingDeletes.contains(fileName)) throw const ApiException(500);
      calls.add('delete($rootDir, $fileName, $deviceSerial)');
    },
    thumbnailUrl: (path, {serial, size}) =>
        Uri.parse('https://quark.local/thumb?path=$path&serial=$serial'),
  );
}

void main() {
  test('names every copy by folder, and drive when not internal', () async {
    final controller = _FakeQuark().controller();

    await controller.load();

    final exact = controller.groups.first;
    expect(exact.isExact, isTrue);
    expect(exact.photos.map((p) => p.location), [
      'Camera',
      'Backup drive · Backups',
      'Files',
    ]);
    expect(controller.groups.last.isExact, isFalse);
    expect(
      controller.thumbnailUrl('USB1:Backups/beach.jpg').toString(),
      contains('serial=USB1'),
    );
  });

  test('marks the spare identical copies and no similar ones', () async {
    final controller = _FakeQuark().controller();

    await controller.load();

    expect(controller.selectedIds, {
      'USB1:Backups/beach.jpg',
      ':beach copy.jpg',
    });
  });

  test('a group always keeps one copy', () async {
    final controller = _FakeQuark().controller();
    await controller.load();

    controller.toggle(':Camera/beach.jpg');
    expect(controller.selectedIds, isNot(contains(':Camera/beach.jpg')));

    controller.toggle(':beach copy.jpg');
    controller.toggle(':Camera/beach.jpg');
    expect(controller.selectedIds, contains(':Camera/beach.jpg'));
    expect(controller.selectedIds, isNot(contains(':beach copy.jpg')));
  });

  test('a reload keeps the marks the user changed', () async {
    final controller = _FakeQuark().controller();
    await controller.load();

    controller.toggle(':beach copy.jpg');
    controller.toggle(':Edits/dog.jpg');
    await controller.load();

    expect(controller.selectedIds, {
      'USB1:Backups/beach.jpg',
      ':Edits/dog.jpg',
    });
  });

  test('a reload marks the spare copies of a new group', () async {
    final quark = _FakeQuark();
    final controller = quark.controller();
    await controller.load();
    controller.toggle(':beach copy.jpg');

    quark.groups = [
      ...quark.groups,
      const DuplicateGroup(
        isExact: true,
        photos: [
          (deviceSerial: '', relPath: 'Camera/cat.jpg'),
          (deviceSerial: '', relPath: 'cat copy.jpg'),
        ],
      ),
    ];
    await controller.load();

    expect(controller.selectedIds, {'USB1:Backups/beach.jpg', ':cat copy.jpg'});
  });

  test('a reload still keeps one copy of every group', () async {
    final quark = _FakeQuark();
    final controller = quark.controller();
    await controller.load();

    quark.groups = [
      const DuplicateGroup(
        isExact: true,
        photos: [
          (deviceSerial: 'USB1', relPath: 'Backups/beach.jpg'),
          (deviceSerial: '', relPath: 'beach copy.jpg'),
        ],
      ),
    ];
    await controller.load();

    expect(controller.selectedIds, {':beach copy.jpg'});
  });

  /// The fake's groups plus one picture saved as a HEIC and a JPEG.
  List<DuplicateGroup> withFormats(_FakeQuark quark) => [
    ...quark.groups,
    const DuplicateGroup(
      isExact: false,
      maxDistance: 1,
      photos: [
        (deviceSerial: '', relPath: 'Camera/IMG_1.HEIC'),
        (deviceSerial: '', relPath: 'Export/IMG_1.jpg'),
      ],
    ),
  ];

  test(
    'a renamed export close enough to the original is the same picture',
    () async {
      final quark = _FakeQuark()
        ..groups = const [
          DuplicateGroup(
            isExact: false,
            maxDistance: 1,
            photos: [
              (deviceSerial: '', relPath: 'Camera/IMG_1.HEIC'),
              (deviceSerial: '', relPath: 'Export/Beach day.jpg'),
            ],
          ),
        ];
      final controller = quark.controller();

      await controller.load();

      expect(controller.formats, ['HEIC', 'JPEG']);
    },
  );

  test('two shots sharing a name in different formats are not', () async {
    final quark = _FakeQuark()
      ..groups = [
        for (final distance in [
          DuplicatesConfig.samePictureMaxDistance + 1,
          null,
        ])
          DuplicateGroup(
            isExact: false,
            maxDistance: distance,
            photos: const [
              (deviceSerial: '', relPath: 'Camera/IMG_1.HEIC'),
              (deviceSerial: '', relPath: 'Export/IMG_1.jpg'),
            ],
          ),
      ];
    final controller = quark.controller();

    await controller.load();

    expect(controller.formats, isEmpty);
  });

  test('offers the formats of a picture saved in several', () async {
    final quark = _FakeQuark();
    final controller = quark.controller();
    await controller.load();
    expect(controller.formats, isEmpty);

    quark.groups = withFormats(quark);
    await controller.load();

    expect(controller.formats, ['HEIC', 'JPEG']);
  });

  test('a preferred format marks the other copy of the same picture', () async {
    final quark = _FakeQuark();
    quark.groups = withFormats(quark);
    final controller = quark.controller();
    await controller.load();

    controller.setPreferredFormat('HEIC');
    expect(controller.selectedIds, {
      'USB1:Backups/beach.jpg',
      ':beach copy.jpg',
      ':Export/IMG_1.jpg',
    });

    controller.setPreferredFormat('JPEG');
    expect(controller.selectedIds, contains(':Camera/IMG_1.HEIC'));
    expect(controller.selectedIds, isNot(contains(':Export/IMG_1.jpg')));

    controller.setPreferredFormat(null);
    expect(controller.selectedIds, {
      'USB1:Backups/beach.jpg',
      ':beach copy.jpg',
    });
  });

  test(
    'a preferred format leaves identical and similar groups alone',
    () async {
      final quark = _FakeQuark();
      quark.groups = withFormats(quark);
      final controller = quark.controller();
      await controller.load();
      controller.toggle(':beach copy.jpg');
      controller.toggle(':Edits/dog.jpg');

      controller.setPreferredFormat('HEIC');

      expect(controller.selectedIds, {
        'USB1:Backups/beach.jpg',
        ':Edits/dog.jpg',
        ':Export/IMG_1.jpg',
      });
    },
  );

  test('a preferred format survives a reload and reaches new groups', () async {
    final quark = _FakeQuark();
    quark.groups = withFormats(quark);
    final controller = quark.controller();
    await controller.load();
    controller.setPreferredFormat('HEIC');

    quark.groups = [
      ...quark.groups,
      const DuplicateGroup(
        isExact: false,
        maxDistance: 2,
        photos: [
          (deviceSerial: '', relPath: 'Camera/IMG_2.heic'),
          (deviceSerial: '', relPath: 'Export/IMG_2.jpeg'),
        ],
      ),
    ];
    await controller.load();

    expect(controller.preferredFormat, 'HEIC');
    expect(
      controller.selectedIds,
      containsAll([':Export/IMG_1.jpg', ':Export/IMG_2.jpeg']),
    );
  });

  test('a toggle after the preference wins until it changes', () async {
    final quark = _FakeQuark();
    quark.groups = withFormats(quark);
    final controller = quark.controller();
    await controller.load();
    controller.setPreferredFormat('HEIC');

    controller.toggle(':Export/IMG_1.jpg');
    await controller.load();
    expect(controller.selectedIds, isNot(contains(':Export/IMG_1.jpg')));

    controller.setPreferredFormat('JPEG');
    expect(controller.selectedIds, contains(':Camera/IMG_1.HEIC'));
  });

  test('deletes each marked copy from its folder, then reloads', () async {
    final quark = _FakeQuark();
    final controller = quark.controller();
    await controller.load();
    quark.calls.clear();

    final failed = await controller.deleteSelected();

    expect(failed, 0);
    expect(quark.calls, [
      'delete(Backups, beach.jpg, USB1)',
      'delete(, beach copy.jpg, null)',
      'load',
    ]);
    expect(controller.isDeleting, isFalse);
  });

  test('counts the copies it could not delete', () async {
    final quark = _FakeQuark()..failingDeletes.add('beach copy.jpg');
    final controller = quark.controller();
    await controller.load();

    expect(await controller.deleteSelected(), 1);
  });

  test('keeps a failed load for the page to word', () async {
    final quark = _FakeQuark()..loadError = const ApiException(500);
    final controller = quark.controller();

    await controller.load();

    expect(controller.error, isA<ApiException>());
    expect(controller.groups, isEmpty);
    expect(controller.isLoading, isFalse);
  });
}
