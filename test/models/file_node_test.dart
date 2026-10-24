import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_node.dart';

void main() {
  group('FileNode.fromJson', () {
    test('uses snake_case fallback keys', () {
      final json = <String, dynamic>{
        'name': 'doc.pdf',
        'size': 500,
        'is_dir': false,
        'device_name': 'Internal',
        'device_path': '/dev/mmcblk0p2',
        'device_serial': '',
        'dir_path': '/documents',
      };

      final node = FileNode.fromJson(json);

      expect(node.isDir, false);
      expect(node.deviceName, 'Internal');
      expect(node.devicePath, '/dev/mmcblk0p2');
      expect(node.deviceSerial, '');
      expect(node.dirPath, '/documents');
    });

    test('defaults missing fields gracefully', () {
      final node = FileNode.fromJson(<String, dynamic>{});

      expect(node.name, '');
      expect(node.size, 0);
      expect(node.isDir, false);
      expect(node.deviceName, '');
      expect(node.devicePath, '');
      expect(node.deviceSerial, '');
      expect(node.dirPath, '');
    });

    for (final (size, want) in <(Object, int)>[
      ('2048', 2048),
      (1024.5, 1024),
      ('not-a-number', 0),
    ]) {
      test('parses size ${size.runtimeType} $size as $want', () {
        final node = FileNode.fromJson(<String, dynamic>{
          'name': 'file.txt',
          'size': size,
        });
        expect(node.size, want);
      });
    }

    for (final (isDir, want) in [
      ('true', true),
      ('True', true),
      ('false', false),
    ]) {
      test('parses isDir from string "$isDir"', () {
        final node = FileNode.fromJson(<String, dynamic>{
          'name': 'folder',
          'isDir': isDir,
        });
        expect(node.isDir, want);
      });
    }
  });

  // #1565: every listing reports when the node last changed, and leaves the
  // field out when it does not know (some archive entries).
  group('FileNode.modifiedAt', () {
    test('parses an RFC 3339 timestamp', () {
      final node = FileNode.fromJson(<String, dynamic>{
        'name': 'notes.txt',
        'modifiedAt': '2026-10-06T14:30:00Z',
      });

      expect(node.modifiedAt, DateTime.utc(2026, 10, 6, 14, 30));
    });

    test('is null when the field is absent', () {
      final node = FileNode.fromJson(<String, dynamic>{'name': 'notes.txt'});

      expect(node.modifiedAt, isNull);
    });

    test('is null for anything that is not a timestamp', () {
      for (final garbage in <Object?>['yesterday', '', 20261006, null]) {
        final node = FileNode.fromJson(<String, dynamic>{
          'name': 'notes.txt',
          'modifiedAt': garbage,
        });

        expect(node.modifiedAt, isNull, reason: '$garbage');
      }
    });
  });

  group('FileNode.apiPath', () {
    for (final (label, name, dirPath, want) in [
      (
        'strips leading and trailing slashes',
        'file.txt',
        '/photos/vacation/',
        'photos/vacation',
      ),
      (
        'falls back to name when dirPath is empty',
        'readme.md',
        '',
        'readme.md',
      ),
      (
        'falls back to name when dirPath is whitespace',
        'readme.md',
        '   ',
        'readme.md',
      ),
      ('strips multiple leading slashes', '', '///deep/path///', 'deep/path'),
    ]) {
      test(label, () {
        final node = FileNode(
          name: name,
          size: 0,
          isDir: false,
          deviceName: '',
          devicePath: '',
          deviceSerial: '',
          dirPath: dirPath,
        );

        expect(node.apiPath, want);
      });
    }
  });

  // Docs and Sheets both filter through matchesSearch. A doc on the device
  // named "Data" used to match every "data" search (#2259).
  group('FileNode.matchesSearch', () {
    const doc = FileNode(
      name: 'test.qdoc',
      size: 1,
      isDir: false,
      deviceName: 'Data',
      devicePath: '/quark/data',
      deviceSerial: '',
      dirPath: 'reports/test.qdoc',
    );

    test('matches the name and the folder path', () {
      expect(doc.matchesSearch('test'), isTrue);
      expect(doc.matchesSearch('reports'), isTrue);
    });

    test('does not match the device name', () {
      expect(doc.matchesSearch('data'), isFalse);
    });
  });

  // The listing snapshot on disk is written with toJson and read back with
  // fromJson (#1781).
  group('FileNode.toJson', () {
    test('round-trips every field through fromJson', () {
      final node = FileNode(
        name: 'clip.mp4',
        size: 2048,
        compressedSize: 512,
        isDir: false,
        deviceName: 'USB Drive',
        devicePath: '/dev/sda1',
        deviceSerial: 'ABC123',
        dirPath: 'videos/clip.mp4',
        fileType: 'video',
        modifiedAt: DateTime.utc(2026, 3, 4, 5, 6, 7),
      );

      final json = node.toJson();
      final back = FileNode.fromJson(json);

      expect(back.toJson(), json);
      expect(back.name, 'clip.mp4');
      expect(back.size, 2048);
      expect(back.compressedSize, 512);
      expect(back.isDir, isFalse);
      expect(back.deviceName, 'USB Drive');
      expect(back.devicePath, '/dev/sda1');
      expect(back.deviceSerial, 'ABC123');
      expect(back.dirPath, 'videos/clip.mp4');
      expect(back.fileType, 'video');
      expect(back.modifiedAt, DateTime.utc(2026, 3, 4, 5, 6, 7));
    });

    test('leaves modifiedAt out when the Quark never gave one', () {
      const node = FileNode(
        name: 'photos',
        size: 0,
        isDir: true,
        deviceName: 'Data',
        devicePath: '/quark/data',
        deviceSerial: '',
        dirPath: 'photos',
      );

      final json = node.toJson();

      expect(json.containsKey('modifiedAt'), isFalse);
      expect(FileNode.fromJson(json).modifiedAt, isNull);
      expect(FileNode.fromJson(json).isDir, isTrue);
    });
  });
}
