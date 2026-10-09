import 'package:flutter/foundation.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/services/vault_backup_service.dart';
import 'package:quark/services/vault_service.dart';
import 'package:quark/utils/error_text.dart';

/// Restoring the vault from a backup drive (#1665): the drives to pick from,
/// the one picked, and the restore itself.
///
/// Service calls arrive as function parameters defaulting to the real static
/// methods, so a test passes fakes without a mocking library.
class VaultRestoreController extends ChangeNotifier {
  /// Creates a controller talking to the real [StorageService] and
  /// [VaultBackupService] unless overridden.
  VaultRestoreController({
    Future<List<StorageDevice>> Function() listDevices =
        StorageService.listDevices,
    Future<VaultRestoreResult> Function({
          required String deviceSerial,
          required String recoveryPassword,
        })
        restoreFromDrive =
        VaultBackupService.restoreFromDrive,
  }) : _listDevices = listDevices,
       _restoreFromDrive = restoreFromDrive;

  final Future<List<StorageDevice>> Function() _listDevices;
  final Future<VaultRestoreResult> Function({
    required String deviceSerial,
    required String recoveryPassword,
  })
  _restoreFromDrive;

  List<StorageDevice> _devices = const [];
  bool _isLoading = false;
  String? _loadError;
  String? _selectedSerial;
  bool _isRestoring = false;
  String? _error;
  VaultRestoreResult? _result;
  bool _vaultLocked = false;
  bool _disposed = false;

  /// The drives a backup can be restored from: external, mounted and enabled,
  /// which is what the Quark means by a managed device.
  List<StorageDevice> get devices => _devices;

  /// Whether the drives are being fetched.
  bool get isLoading => _isLoading;

  /// User-facing copy for a failed drive listing, or null. From [Errors].
  String? get loadError => _loadError;

  /// The serial of the picked drive, or null when none is.
  String? get selectedSerial => _selectedSerial;

  /// Whether a restore is in flight.
  bool get isRestoring => _isRestoring;

  /// User-facing copy for the last failed restore, or null. From [Errors].
  String? get error => _error;

  /// What the restore did, or null until one succeeds.
  VaultRestoreResult? get result => _result;

  /// Whether the vault locked itself before the restore ran. The page shows
  /// the unlock form again.
  bool get vaultLocked => _vaultLocked;

  /// Fetches the drives. A lone drive is picked for the user.
  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    _notify();
    try {
      _devices = (await _listDevices())
          .where(
            (d) =>
                !d.isInternal &&
                d.isEnabled &&
                !d.isUnmounted &&
                d.serial.isNotEmpty,
          )
          .toList();
      if (!_devices.any((d) => d.serial == _selectedSerial)) {
        _selectedSerial = _devices.length == 1 ? _devices.single.serial : null;
      }
    } catch (error) {
      _loadError = Errors.message(error, 'load your drives');
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  /// Picks the drive with [serial].
  void selectDevice(String serial) {
    _selectedSerial = serial;
    _notify();
  }

  /// Restores the backup on the picked drive, opening it with
  /// [recoveryPassword]. True on success, with [result] set.
  Future<bool> restore(String recoveryPassword) async {
    final serial = _selectedSerial;
    if (serial == null || recoveryPassword.isEmpty || _isRestoring) {
      return false;
    }
    _isRestoring = true;
    _error = null;
    _notify();
    try {
      _result = await _restoreFromDrive(
        deviceSerial: serial,
        recoveryPassword: recoveryPassword,
      );
      return true;
    } on VaultLockedException {
      _vaultLocked = true;
      return false;
    } catch (error) {
      _error = Errors.vaultRestore(error);
      return false;
    } finally {
      _isRestoring = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
