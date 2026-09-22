import 'package:flutter/foundation.dart';
import 'package:quark/models/repair_status.dart';
import 'package:quark/services/repair_service.dart';
import 'package:quark/utils/error_text.dart';

/// The repair installation section of the settings page (#2121).
///
/// Service calls arrive as function parameters defaulting to the real static
/// methods, so a test passes fakes without a mocking library.
class RepairController extends ChangeNotifier {
  /// Creates a controller talking to the real [RepairService] unless
  /// overridden.
  RepairController({
    Future<RepairStatus> Function() getStatus = RepairService.getStatus,
    Future<void> Function() repair = RepairService.repair,
  }) : _getStatus = getStatus,
       _repair = repair;

  final Future<RepairStatus> Function() _getStatus;
  final Future<void> Function() _repair;

  RepairStatus? _status;
  bool _isLoading = false;
  bool _isWorking = false;
  String? _error;
  bool _disposed = false;

  /// The last status the Quark sent, or null before the first load.
  RepairStatus? get status => _status;

  /// Whether the status is being fetched.
  bool get isLoading => _isLoading;

  /// Whether a repair request is in flight.
  bool get isWorking => _isWorking;

  /// User-facing copy for the last failure, or null. Always from [Errors].
  String? get error => _error;

  /// Whether the section has nothing to offer on this Quark: not Linux, or
  /// not the installed service. An outdated unit is not hidden, because the
  /// one-time `sudo quark install` it needs is the only way to get the fix.
  bool get isHidden {
    final status = _status;
    return status != null && !status.available && !needsInstall;
  }

  /// Whether the installed unit needs `sudo quark install` once first.
  bool get needsInstall => _status?.reason == RepairStatus.unitOutdated;

  /// Fetches the status.
  Future<void> load() async {
    _isLoading = true;
    _notify();
    try {
      _status = await _getStatus();
      _error = null;
    } catch (error) {
      _error = Errors.message(
        error,
        'check whether the installation can be repaired',
      );
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  /// Asks the Quark to restart and repair itself. True on success.
  Future<bool> repair() async {
    _isWorking = true;
    _error = null;
    _notify();
    try {
      await _repair();
      return true;
    } catch (error) {
      _error = Errors.message(error, 'repair the installation');
      return false;
    } finally {
      _isWorking = false;
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
