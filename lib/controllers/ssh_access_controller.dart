import 'package:flutter/foundation.dart';
import 'package:quark/models/ssh_access_status.dart';
import 'package:quark/services/ssh_access_service.dart';
import 'package:quark/utils/error_text.dart';

/// The SSH access section of the settings page (#2131): its status and every
/// change an admin can make.
///
/// Service calls arrive as function parameters defaulting to the real static
/// methods, so a test passes fakes without a mocking library.
class SshAccessController extends ChangeNotifier {
  /// Creates a controller talking to the real [SshAccessService] unless
  /// overridden.
  SshAccessController({
    Future<SshAccessStatus> Function() getStatus = SshAccessService.getStatus,
    Future<void> Function(bool enabled) setEnabled =
        SshAccessService.setEnabled,
    Future<void> Function(String key) addKey = SshAccessService.addKey,
    Future<void> Function(String fingerprint) removeKey =
        SshAccessService.removeKey,
    Future<void> Function(String password) setPassword =
        SshAccessService.setPassword,
    Future<void> Function() clearPassword = SshAccessService.clearPassword,
  }) : _getStatus = getStatus,
       _setEnabled = setEnabled,
       _addKey = addKey,
       _removeKey = removeKey,
       _setPassword = setPassword,
       _clearPassword = clearPassword;

  final Future<SshAccessStatus> Function() _getStatus;
  final Future<void> Function(bool enabled) _setEnabled;
  final Future<void> Function(String key) _addKey;
  final Future<void> Function(String fingerprint) _removeKey;
  final Future<void> Function(String password) _setPassword;
  final Future<void> Function() _clearPassword;

  SshAccessStatus? _status;
  bool _isLoading = false;
  bool _isWorking = false;
  String? _error;
  bool _disposed = false;

  /// The last status the Quark sent, or null before the first load.
  SshAccessStatus? get status => _status;

  /// Whether the status is being fetched.
  bool get isLoading => _isLoading;

  /// Whether a change is in flight. The section disables its controls.
  bool get isWorking => _isWorking;

  /// User-facing copy for the last failure, or null. Always from [Errors].
  String? get error => _error;

  /// Why SSH access can't be managed, with the fix, or null when it can (or
  /// the status is not known yet).
  String? get unavailableReason {
    final status = _status;
    if (status == null || status.available) return null;
    return Errors.sshUnavailable(status.reason);
  }

  /// Fetches the status.
  Future<void> load() async {
    _isLoading = true;
    _notify();
    try {
      _status = await _getStatus();
      _error = null;
    } catch (error) {
      _error = Errors.message(error, 'load SSH access');
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  /// Turns SSH access on or off. True on success.
  Future<bool> setEnabled(bool enabled) => _change(
    () => _setEnabled(enabled),
    enabled ? 'turn on SSH access' : 'turn off SSH access',
  );

  /// Allows [key] to sign in. True on success.
  Future<bool> addKey(String key) => _change(() => _addKey(key), 'add the key');

  /// Stops the key with [fingerprint] signing in. True on success.
  Future<bool> removeKey(String fingerprint) =>
      _change(() => _removeKey(fingerprint), 'remove the key');

  /// Sets the login password. True on success.
  Future<bool> setPassword(String password) =>
      _change(() => _setPassword(password), 'set the password', reload: false);

  /// Clears the login password. True on success.
  Future<bool> clearPassword() =>
      _change(_clearPassword, 'clear the password', reload: false);

  /// Runs [request], then reloads the status when it can have changed.
  /// [action] names what was attempted, for [Errors.message].
  Future<bool> _change(
    Future<void> Function() request,
    String action, {
    bool reload = true,
  }) async {
    _isWorking = true;
    _error = null;
    _notify();
    try {
      await request();
      if (reload) _status = await _getStatus();
      return true;
    } catch (error) {
      _error = Errors.message(error, action);
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
