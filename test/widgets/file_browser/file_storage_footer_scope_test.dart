import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/health_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/file_browser/file_storage_footer_scope.dart';

// #2895: with a USB drive as Default Storage and both drives checked under
// Filter devices, the footer showed only the built-in disk's health reading.
// It has to report the drives the view is showing.
void main() {
  const gib = 1 << 30;
  const builtIn = StorageDevice(
    name: 'Built-in storage',
    devicePath: '/dev/mmcblk0',
    mountPoint: '/',
    fileSystem: 'ext4',
    totalBytes: 28 * gib,
    usedBytes: 9 * gib,
    availableBytes: 19 * gib,
    isInternal: true,
    isEnabled: true,
  );
  const seagate = StorageDevice(
    name: 'Seagate - BUP Slim',
    devicePath: '/dev/sda1',
    mountPoint: '/mnt/seagate',
    fileSystem: 'exfat',
    totalBytes: 1800 * gib,
    usedBytes: 3 * gib,
    availableBytes: 1797 * gib,
    isInternal: false,
    isEnabled: true,
    serial: 'NA123',
    role: 'default-storage',
  );
  const unplugged = StorageDevice(
    name: 'Old stick',
    devicePath: '/dev/sdb1',
    mountPoint: '',
    fileSystem: 'vfat',
    totalBytes: 0,
    usedBytes: 0,
    availableBytes: 0,
    isInternal: false,
    isEnabled: false,
    serial: 'OLD1',
  );
  final health = HealthStatus(
    healthy: true,
    alerts: const [],
    cpuPercent: 0,
    cpuCorePercents: const [],
    memPercent: 0,
    memUsedBytes: 0,
    memTotalBytes: 0,
    diskPercent: 32,
    diskUsedBytes: 9 * gib,
    diskTotalBytes: 28 * gib,
    temperatureCelsius: 0,
  );

  test('sums every checked drive and calls it All drives', () {
    final scope = FileStorageFooterScope.of(
      devices: const [builtIn, seagate],
      activeDevicePaths: {builtIn.devicePath, seagate.devicePath},
      health: health,
    );

    expect(scope.label, kStorageFooterAllDrives);
    expect(scope.explanation, kStorageFooterAllDrivesExplanation);
    expect(scope.usedBytes, 12 * gib);
    expect(scope.totalBytes, 1828 * gib);
    expect(scope.usedFraction, closeTo(12 / 1828, 1e-9));
  });

  test('names the one plugged-in drive left checked', () {
    final scope = FileStorageFooterScope.of(
      devices: const [builtIn, seagate],
      activeDevicePaths: {seagate.devicePath},
      health: health,
    );

    expect(scope.label, 'Seagate - BUP Slim');
    expect(scope.explanation, kStorageFooterDriveExplanation);
    expect(scope.usedBytes, 3 * gib);
    expect(scope.totalBytes, 1800 * gib);
  });

  test('keeps Device storage for the built-in disk alone', () {
    final scope = FileStorageFooterScope.of(
      devices: const [builtIn, seagate],
      activeDevicePaths: {builtIn.devicePath},
      health: health,
    );

    expect(scope.label, kStorageFooterScope);
    expect(scope.explanation, kStorageFooterExplanation);
    expect(scope.usedBytes, 9 * gib);
    expect(scope.totalBytes, 28 * gib);
  });

  test('leaves out a drive that is not mounted', () {
    final scope = FileStorageFooterScope.of(
      devices: const [builtIn, unplugged],
      activeDevicePaths: {builtIn.devicePath, unplugged.devicePath},
      health: health,
    );

    expect(scope.label, kStorageFooterScope);
    expect(scope.totalBytes, 28 * gib);
  });

  test('falls back to the health reading without a device list', () {
    final scope = FileStorageFooterScope.of(
      devices: const [],
      activeDevicePaths: const {},
      health: health,
    );

    expect(scope.label, kStorageFooterScope);
    expect(scope.usedBytes, 9 * gib);
    expect(scope.totalBytes, 28 * gib);
  });

  test('has no reading before anything has loaded', () {
    final scope = FileStorageFooterScope.of(
      devices: const [],
      activeDevicePaths: const {},
    );

    expect(scope.label, kStorageFooterScope);
    expect(scope.usedBytes, isNull);
    expect(scope.usedFraction, 0);
  });
}
