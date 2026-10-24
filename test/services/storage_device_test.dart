import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/storage_service.dart';

void main() {
  group('StorageDevice.fromJson', () {
    test('takes the serial from usbInfo', () {
      final device = StorageDevice.fromJson(<String, dynamic>{
        'name': 'USB Drive',
        'usbInfo': {'serial': 'ABC123'},
        'categories': {'documents': 100, 'media': 200},
      });

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

      // A null usbInfo, a usbInfo with no serial, and null categories read
      // the same as missing ones.
      for (final json in <Map<String, dynamic>>[
        {'usbInfo': null},
        {'usbInfo': <String, dynamic>{}},
        {'categories': null},
      ]) {
        final device = StorageDevice.fromJson(json);
        expect(device.serial, '', reason: '$json');
        expect(device.categories, isEmpty, reason: '$json');
      }
    });
  });

  /// A device of [totalBytes] with [usedBytes] of it used.
  StorageDevice sized(int totalBytes, int usedBytes) => StorageDevice(
    name: 'Drive',
    devicePath: '',
    mountPoint: '',
    fileSystem: '',
    totalBytes: totalBytes,
    usedBytes: usedBytes,
    availableBytes: totalBytes - usedBytes,
    isInternal: false,
    isEnabled: true,
  );

  group('StorageDevice.usedPercent', () {
    test('calculates percentage correctly', () {
      expect(sized(1000, 250).usedPercent, 25.0);
    });

    test('returns 0 when totalBytes is 0', () {
      expect(sized(0, 0).usedPercent, 0.0);
    });
  });

  group('StorageDevice.formatBytes', () {
    for (final (bytes, want) in [
      (2000000000000, '1.8 TB'),
      (1500000000, '1.4 GB'),
      (5000000, '4.8 MB'),
      (512, '512 B'),
      (0, '0 B'),
    ]) {
      test('formats $bytes as $want', () {
        expect(StorageDevice.formatBytes(bytes), want);
      });
    }
  });

  group('StorageDevice.usedDisplay', () {
    test('combines used and total with formatBytes', () {
      expect(sized(1000000000, 500000000).usedDisplay, '476.8 MB / 953.7 MB');
    });
  });
}
