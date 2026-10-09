import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/vault_restore_controller.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/services/vault_backup_service.dart';
import 'package:quark/services/vault_service.dart';
import 'package:quark/utils/error_text.dart';

StorageDevice _drive(
  String serial, {
  bool isInternal = false,
  bool isEnabled = true,
  String mountPoint = '/mnt/usb',
}) => StorageDevice(
  name: 'Drive $serial',
  devicePath: '/dev/sda1',
  mountPoint: mountPoint,
  fileSystem: 'ext4',
  totalBytes: 1024,
  usedBytes: 512,
  availableBytes: 512,
  isInternal: isInternal,
  isEnabled: isEnabled,
  serial: serial,
);

/// A controller whose restore answers with [restore], recording its calls.
VaultRestoreController _controller({
  List<StorageDevice> devices = const [],
  Future<VaultRestoreResult> Function()? restore,
  List<(String, String)>? calls,
}) => VaultRestoreController(
  listDevices: () async => devices,
  restoreFromDrive: ({required deviceSerial, required recoveryPassword}) async {
    calls?.add((deviceSerial, recoveryPassword));
    return restore == null ? const VaultRestoreResult() : restore();
  },
);

/// #1665: the restore-from-backup-drive flow's state.
void main() {
  test('offers only external, enabled, mounted drives with a serial', () async {
    final controller = _controller(
      devices: [
        _drive('', isInternal: true),
        _drive('OFF', isEnabled: false),
        _drive('UNMOUNTED', mountPoint: ''),
        _drive(''),
        _drive('A'),
        _drive('B'),
      ],
    );
    await controller.load();

    expect(controller.devices.map((d) => d.serial), ['A', 'B']);
    expect(controller.selectedSerial, isNull, reason: 'two drives: no guess');
    expect(controller.isLoading, isFalse);
    expect(controller.loadError, isNull);
  });

  test('a lone drive is picked for the user', () async {
    final controller = _controller(devices: [_drive('ONLY')]);
    await controller.load();
    expect(controller.selectedSerial, 'ONLY');
  });

  test('a failed drive listing reads as Errors copy', () async {
    final controller = VaultRestoreController(
      listDevices: () async => throw const ApiException(500),
    );
    await controller.load();
    expect(
      controller.loadError,
      Errors.message(const ApiException(500), 'load your drives'),
    );
    expect(controller.devices, isEmpty);
  });

  test('restores from the picked drive and keeps the result', () async {
    final calls = <(String, String)>[];
    final controller = _controller(
      devices: [_drive('A'), _drive('B')],
      calls: calls,
      restore: () async =>
          const VaultRestoreResult(entriesImported: 3, entriesSkipped: 1),
    );
    await controller.load();

    expect(await controller.restore('pw'), isFalse, reason: 'no drive picked');
    controller.selectDevice('B');
    expect(await controller.restore(''), isFalse, reason: 'no password');
    expect(calls, isEmpty);

    expect(await controller.restore('pw'), isTrue);
    expect(calls, [('B', 'pw')]);
    expect(controller.result?.entriesImported, 3);
    expect(controller.result?.entriesSkipped, 1);
    expect(controller.error, isNull);
    expect(controller.isRestoring, isFalse);
  });

  test('a rejected backup reads as the restore copy', () async {
    final controller = _controller(
      devices: [_drive('A')],
      restore: () async => throw const ApiException(400),
    );
    await controller.load();

    expect(await controller.restore('wrong'), isFalse);
    expect(controller.error, Errors.vaultBackupRejected);
    expect(controller.result, isNull);
    expect(controller.vaultLocked, isFalse);
  });

  test('an unplugged vault drive does not read as a busy Quark', () async {
    final controller = _controller(
      devices: [_drive('A')],
      restore: () async => throw const ApiException(503),
    );
    await controller.load();

    expect(await controller.restore('pw'), isFalse);
    expect(controller.error, Errors.vaultDriveDisconnected);
  });

  test('a vault that locked itself is reported, not an error', () async {
    final controller = _controller(
      devices: [_drive('A')],
      restore: () async => throw VaultLockedException(),
    );
    await controller.load();

    expect(await controller.restore('pw'), isFalse);
    expect(controller.vaultLocked, isTrue);
    expect(controller.error, isNull);
  });

  test('does not notify after dispose', () async {
    var notified = 0;
    final controller = _controller(devices: [_drive('A')])
      ..addListener(() => notified++);
    final loading = controller.load();
    controller.dispose();
    final before = notified;
    await loading;
    expect(notified, before);
  });
}
