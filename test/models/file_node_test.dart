import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_node.dart';

void main() {
  group('FileNode.fromJson', () {
    test('parses a fully populated JSON payload', () {
      final json = <String, dynamic>{
        'name': 'photo.jpg',
        'size': 1024,
        'isDir': false,
        'deviceName': 'USB Drive',
        'devicePath': '/dev/sda1',
        'deviceSerial': 'ABC123',
        'dirPath': '/photos/vacation',
      };

      final node = FileNode.fromJson(json);

      expect(node.name, 'photo.jpg');
      expect(node.size, 1024);
      expect(node.isDir, false);
      expect(node.deviceName, 'USB Drive');
      expect(node.devicePath, '/dev/sda1');
      expect(node.deviceSerial, 'ABC123');
      expect(node.dirPath, '/photos/vacation');
    });

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

    test('parses size from string', () {
      final json = <String, dynamic>{'name': 'file.txt', 'size': '2048'};

      final node = FileNode.fromJson(json);
      expect(node.size, 2048);
    });

    test('parses size from double', () {
      final json = <String, dynamic>{'name': 'file.txt', 'size': 1024.5};

      final node = FileNode.fromJson(json);
      expect(node.size, 1024);
    });

    test('parses invalid size string as 0', () {
      final json = <String, dynamic>{
        'name': 'file.txt',
        'size': 'not-a-number',
      };

      final node = FileNode.fromJson(json);
      expect(node.size, 0);
    });

    test('parses isDir from string "true"', () {
      final json = <String, dynamic>{'name': 'folder', 'isDir': 'true'};

      final node = FileNode.fromJson(json);
      expect(node.isDir, true);
    });

    test('parses isDir from string "True" (case insensitive)', () {
      final json = <String, dynamic>{'name': 'folder', 'isDir': 'True'};

      final node = FileNode.fromJson(json);
      expect(node.isDir, true);
    });

    test('parses isDir from string "false"', () {
      final json = <String, dynamic>{'name': 'file.txt', 'isDir': 'false'};

      final node = FileNode.fromJson(json);
      expect(node.isDir, false);
    });
  });

  group('FileNode.apiPath', () {
    test('returns dirPath with leading/trailing slashes stripped', () {
      const node = FileNode(
        name: 'file.txt',
        size: 0,
        isDir: false,
        deviceName: '',
        devicePath: '',
        deviceSerial: '',
        dirPath: '/photos/vacation/',
      );

      expect(node.apiPath, 'photos/vacation');
    });

    test('falls back to name when dirPath is empty', () {
      const node = FileNode(
        name: 'readme.md',
        size: 0,
        isDir: false,
        deviceName: '',
        devicePath: '',
        deviceSerial: '',
        dirPath: '',
      );

      expect(node.apiPath, 'readme.md');
    });

    test('falls back to name when dirPath is whitespace', () {
      const node = FileNode(
        name: 'readme.md',
        size: 0,
        isDir: false,
        deviceName: '',
        devicePath: '',
        deviceSerial: '',
        dirPath: '   ',
      );

      expect(node.apiPath, 'readme.md');
    });

    test('strips multiple leading slashes', () {
      const node = FileNode(
        name: '',
        size: 0,
        isDir: true,
        deviceName: '',
        devicePath: '',
        deviceSerial: '',
        dirPath: '///deep/path///',
      );

      expect(node.apiPath, 'deep/path');
    });
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
}
