import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/trash_controller.dart';
import 'package:quark/models/trash_item.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';

StorageDevice _device(String path, String serial, {bool internal = false}) =>
    StorageDevice(
      name: path,
      devicePath: path,
      mountPoint: '/mnt$path',
      fileSystem: 'ext4',
      totalBytes: 0,
      usedBytes: 0,
      availableBytes: 0,
      isInternal: internal,
      isEnabled: true,
      serial: serial,
    );

TrashItem _item(
  String trashName, {
  required int day,
  String originalPath = 'Docs/a.txt',
}) => TrashItem(
  trashName: trashName,
  name: trashName,
  originalPath: originalPath,
  isDir: false,
  size: 1,
  trashedAt: DateTime.utc(2026, 9, day),
  expiresAt: DateTime.utc(2026, 9, 13, 1),
);

void main() {
  final now = DateTime.utc(2026, 9, 11);
  final internal = _device('/internal', '', internal: true);
  final usb = _device('/usb', 'USB1');

  late Map<String, List<TrashItem>> trash;

  /// Folders inside trashed items, keyed `serial|trashName|path`.
  late Map<String, TrashContents> folders;
  late List<String> calls;

  TrashController controller({
    List<StorageDevice>? devices,
    Object? restoreError,
    TrashLocation? location,
  }) => TrashController(
    location: location,
    clock: () => now,
    listDevices: () async => devices ?? [internal, usb],
    listTrash: (serial, {deviceName = ''}) async {
      if (!trash.containsKey(serial)) throw const ApiException(404);
      return TrashListing(
        retentionDays: 30,
        items: [
          for (final i in trash[serial]!)
            TrashItem.fromJson(
              {
                'trashName': i.trashName,
                'name': i.name,
                'originalPath': i.originalPath,
                'trashedAt': i.trashedAt.toIso8601String(),
                'expiresAt': i.expiresAt.toIso8601String(),
              },
              deviceSerial: serial,
              deviceName: deviceName,
            ),
        ],
      );
    },
    listContents: (serial, trashName, path) async {
      calls.add('contents [$serial] $trashName/$path');
      final contents = folders['$serial|$trashName|$path'];
      if (contents == null) throw const ApiException(404);
      return contents;
    },
    restoreItems: (serial, items) async {
      calls.add('restore [$serial] ${items.join(',')}');
      if (restoreError != null) throw restoreError;
      return [for (final i in items) '$i'];
    },
    deleteItems: (serial, items) async {
      calls.add('delete [$serial] ${items.join(',')}');
      return items.length;
    },
    emptyTrash: (serial) async {
      calls.add('empty [$serial]');
      return 1;
    },
  );

  setUp(() {
    trash = {
      '': [_item('in1', day: 3), _item('in2', day: 2, originalPath: 'top.txt')],
      'USB1': [_item('usb1', day: 1, originalPath: '')],
    };
    folders = {
      'USB1|x_album|': TrashContents(
        originalPath: 'Pictures/album',
        expiresAt: DateTime.utc(2026, 9, 13, 1),
        items: const [
          TrashContentsItem(name: '2024', path: '2024', isDir: true, size: 3),
          TrashContentsItem(
            name: 'cover.jpg',
            path: 'cover.jpg',
            isDir: false,
            size: 5,
          ),
        ],
      ),
      'USB1|x_album|2024': TrashContents(
        originalPath: 'Pictures/album/2024',
        expiresAt: DateTime.utc(2026, 9, 13, 1),
        items: const [
          TrashContentsItem(
            name: 'one.jpg',
            path: '2024/one.jpg',
            isDir: false,
            size: 3,
          ),
        ],
      ),
    };
    calls = [];
  });

  const album = (serial: 'USB1', trashName: 'x_album', path: '');
  const album2024 = (serial: 'USB1', trashName: 'x_album', path: '2024');

  test('merges every device trash into one listing', () async {
    final c = controller();
    await c.load();

    expect(c.nodes!.map((n) => n.apiPath), [
      '.trash/in1',
      '.trash/in2',
      '.trash/usb1',
    ]);
    expect(c.nodes!.last.deviceSerial, 'USB1');
    expect(TrashController.refFor(c.nodes!.last), const TrashRef('usb1'));
    expect(c.retentionDays, 30);
    expect(await c.listing, c.nodes);
  });

  test('a drive whose trash is gone is skipped, not an error', () async {
    trash.remove('USB1');
    final c = controller();
    await c.load();

    expect(c.nodes!.map((n) => n.name), ['in1', 'in2']);
  });

  test('hiding a device lists only the rest', () async {
    final c = controller();
    await c.load();
    await c.toggleDevice('/usb');

    expect(c.nodes!.map((n) => n.name), ['in1', 'in2']);
  });

  test('the subtitle names the folder and the days left', () async {
    final c = controller();
    await c.load();

    // Expires 2 days and an hour from now: rounds up to three.
    expect(c.subtitleFor(c.nodes![0]), 'From /Docs · 3 days left');
    expect(c.subtitleFor(c.nodes![1]), 'From / · 3 days left');
    expect(
      c.subtitleFor(c.nodes![2]),
      'Original location unknown · 3 days left',
    );
  });

  test('restores one request per device and drops what came back', () async {
    final c = controller();
    await c.load();
    c.toggleSelection(c.nodes![0], enterSelectionMode: true);
    c.toggleSelection(c.nodes![2], enterSelectionMode: false);

    final count = await c.restore(c.selectedNodes);

    expect(count, 2);
    expect(calls, ['restore [] in1', 'restore [USB1] usb1']);
    expect(c.nodes!.map((n) => n.name), ['in2']);
    expect(c.selectionMode, isFalse);
  });

  test('a refused restore keeps the items and rethrows', () async {
    final c = controller(restoreError: const ApiException(409));
    await c.load();

    await expectLater(
      c.restore([c.nodes!.first]),
      throwsA(isA<ApiException>()),
    );
    expect(c.nodes, hasLength(3));
  });

  test('deletes for good and empties every shown device', () async {
    final c = controller();
    await c.load();

    expect(await c.deletePermanently([c.nodes!.first]), 1);
    expect(await c.empty(), 2);

    expect(calls, ['delete [] in1', 'empty []', 'empty [USB1]']);
    expect(c.nodes, isEmpty);
  });

  test('with no device list, falls back to the internal trash', () async {
    final c = controller(devices: const []);
    await c.load();

    expect(c.nodes!.map((n) => n.name), ['in1', 'in2']);
  });

  group('browsing a trashed folder', () {
    test('lists its contents with paths that address them', () async {
      final c = controller(location: album);
      await c.load();

      expect(c.nodes!.map((n) => n.apiPath), [
        '.trash/x_album/2024',
        '.trash/x_album/cover.jpg',
      ]);
      expect(c.nodes!.first.isDir, isTrue);
      expect(c.nodes!.first.deviceSerial, 'USB1');
      expect(
        TrashController.refFor(c.nodes!.first),
        const TrashRef('x_album', '2024'),
      );
      expect(c.breadcrumbPath, '/album');
      expect(
        c.subtitleFor(c.nodes!.last),
        'From /Pictures/album · 3 days left',
      );
    });

    test('opens a subfolder and back up to the root', () async {
      final c = controller(location: album);
      await c.load();
      await c.open(album2024);

      expect(c.nodes!.single.apiPath, '.trash/x_album/2024/one.jpg');
      expect(c.breadcrumbPath, '/album/2024');
      expect(c.locationAt('/album'), album);
      expect(TrashController.parentOf(album2024), album);
      expect(TrashController.parentOf(album), isNull);
      expect(
        c.subtitleFor(c.nodes!.single),
        'From /Pictures/album/2024 · 3 days left',
      );

      await c.open(null);
      expect(c.location, isNull);
      expect(c.nodes!.map((n) => n.name), ['in1', 'in2', 'usb1']);
    });

    test('restores and deletes nested items by path', () async {
      final c = controller(location: album);
      await c.load();
      c.toggleSelection(c.nodes![0], enterSelectionMode: true);
      c.toggleSelection(c.nodes![1], enterSelectionMode: false);

      expect(await c.restore(c.selectedNodes), 2);
      expect(calls.last, 'restore [USB1] x_album/2024,x_album/cover.jpg');
      expect(c.nodes, isEmpty);
      expect(c.selectionMode, isFalse);

      await c.open(album2024);
      expect(await c.deletePermanently([c.nodes!.single]), 1);
      expect(calls.last, 'delete [USB1] x_album/2024/one.jpg');
      expect(c.nodes, isEmpty);
    });

    test('a folder that disappears climbs to the nearest level left', () async {
      final c = controller(location: album2024);
      await c.load();
      expect(c.location, album2024);

      // Restored or deleted from another client.
      folders.remove('USB1|x_album|2024');
      await c.load();
      expect(c.location, album);
      expect(c.nodes!.map((n) => n.name), ['2024', 'cover.jpg']);

      // The whole trashed folder is purged: back to the trash root.
      folders.clear();
      await c.load();
      expect(c.location, isNull);
      expect(c.nodes!.map((n) => n.name), ['in1', 'in2', 'usb1']);
    });

    test(
      'a deep link to a folder that never existed lands at the root',
      () async {
        final c = controller(
          location: (serial: 'USB1', trashName: 'gone', path: 'a/b'),
        );
        await c.load();

        expect(c.location, isNull);
        expect(calls, [
          'contents [USB1] gone/a/b',
          'contents [USB1] gone/a',
          'contents [USB1] gone/',
        ]);
      },
    );
  });
}
