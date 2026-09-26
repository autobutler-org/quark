import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/storage_service.dart';

void main() {
  group('StorageDevice.fromJson', () {
    test('parses a fully populated JSON payload', () {
      final json = <String, dynamic>{
        'name': 'USB Drive',
        'devicePath': '/dev/sda1',
        'mountPoint': '/mnt/usb',
        'fileSystem': 'ext4',
        'totalBytes': 1000000000,
        'usedBytes': 250000000,
        'availableBytes': 750000000,
        'isInternal': false,
        'isEnabled': true,
        'model': 'SanDisk Ultra',
        'usbInfo': {'serial': 'ABC123'},
        'categories': {'documents': 100, 'media': 200},
      };

      final device = StorageDevice.fromJson(json);

      expect(device.name, 'USB Drive');
      expect(device.devicePath, '/dev/sda1');
      expect(device.mountPoint, '/mnt/usb');
      expect(device.fileSystem, 'ext4');
      expect(device.totalBytes, 1000000000);
      expect(device.usedBytes, 250000000);
      expect(device.availableBytes, 750000000);
      expect(device.isInternal, false);
      expect(device.isEnabled, true);
      expect(device.model, 'SanDisk Ultra');
      expect(device.serial, 'ABC123');
      expect(device.categories, {'documents': 100, 'media': 200});
    });

    test('defaults missing fields gracefully', () {
      final device = StorageDevice.fromJson(<String, dynamic>{});

      expect(device.name, '');
      expect(device.devicePath, '');
      expect(device.mountPoint, '');
      expect(device.fileSystem, '');
      expect(device.totalBytes, 0);
      expect(device.usedBytes, 0);
      expect(device.availableBytes, 0);
      expect(device.isInternal, false);
      expect(device.isEnabled, false);
      expect(device.model, '');
      expect(device.serial, '');
      expect(device.categories, isEmpty);
    });

    test('handles null usbInfo', () {
      final json = <String, dynamic>{
        'name': 'Internal',
        'isInternal': true,
        'isEnabled': true,
        'usbInfo': null,
      };

      final device = StorageDevice.fromJson(json);
      expect(device.serial, '');
      expect(device.isInternal, true);
    });

    test('handles missing serial inside usbInfo', () {
      final json = <String, dynamic>{
        'name': 'Weird Drive',
        'usbInfo': <String, dynamic>{},
      };

      final device = StorageDevice.fromJson(json);
      expect(device.serial, '');
    });

    test('handles null categories', () {
      final json = <String, dynamic>{'name': 'Drive', 'categories': null};

      final device = StorageDevice.fromJson(json);
      expect(device.categories, isEmpty);
    });
  });

  group('StorageDevice.usedPercent', () {
    test('calculates percentage correctly', () {
      const device = StorageDevice(
        name: 'Test',
        devicePath: '',
        mountPoint: '',
        fileSystem: '',
        totalBytes: 1000,
        usedBytes: 250,
        availableBytes: 750,
        isInternal: false,
        isEnabled: true,
      );

      expect(device.usedPercent, 25.0);
    });

    test('returns 0 when totalBytes is 0', () {
      const device = StorageDevice(
        name: 'Empty',
        devicePath: '',
        mountPoint: '',
        fileSystem: '',
        totalBytes: 0,
        usedBytes: 0,
        availableBytes: 0,
        isInternal: false,
        isEnabled: false,
      );

      expect(device.usedPercent, 0.0);
    });
  });

  group('StorageDevice.formatBytes', () {
    test('formats TB', () {
      expect(StorageDevice.formatBytes(2000000000000), '1.8 TB');
    });

    test('formats GB', () {
      expect(StorageDevice.formatBytes(1500000000), '1.4 GB');
    });

    test('formats MB', () {
      expect(StorageDevice.formatBytes(5000000), '4.8 MB');
    });

    test('formats small values as bytes', () {
      expect(StorageDevice.formatBytes(512), '512 B');
    });

    test('formats zero', () {
      expect(StorageDevice.formatBytes(0), '0 B');
    });
  });

  group('StorageDevice.usedDisplay', () {
    test('combines used and total with formatBytes', () {
      const device = StorageDevice(
        name: 'Drive',
        devicePath: '',
        mountPoint: '',
        fileSystem: '',
        totalBytes: 1000000000,
        usedBytes: 500000000,
        availableBytes: 500000000,
        isInternal: false,
        isEnabled: true,
      );

      expect(device.usedDisplay, '476.8 MB / 953.7 MB');
    });
  });
}
