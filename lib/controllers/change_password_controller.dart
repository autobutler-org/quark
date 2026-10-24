import 'package:flutter/foundation.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';

/// The change-password dialog's one service call, kept out of the Settings
/// page (#3022).
///
/// The page owns the dialog and closes it; this owns the request and what the
/// dialog shows while it runs and after it fails.
///
/// The service call arrives as a function parameter defaulting to the real
/// static method, so a test passes a fake without a mocking library.
class ChangePasswordController extends ChangeNotifier with SafeNotifier {
  /// Creates a controller talking to the real [AuthService] unless overridden.
  ChangePasswordController({
    Future<void> Function({
          required String currentPassword,
          required String newPassword,
        })
        changePasswordRequest =
        AuthService.changePassword,
  }) : _changePasswordRequest = changePasswordRequest;

  final Future<void> Function({
    required String currentPassword,
    required String newPassword,
  })
  _changePasswordRequest;

  bool _isWorking = false;
  String? _error;

  /// Whether a change is in flight. The dialog disables its fields and
  /// buttons meanwhile.
  bool get isWorking => _isWorking;

  /// User-facing copy for the last failure, or null. Always from [Errors].
  String? get error => _error;

  /// Changes the signed-in account's password.
  ///
  /// Returns whether it changed; on false, [error] says why. A second call
  /// while one is in flight changes nothing and returns false.
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_isWorking) return false;
    _isWorking = true;
    _error = null;
    notifyListeners();
    try {
      await _changePasswordRequest(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      return true;
    } catch (error) {
      _error = Errors.message(error, 'change your password');
      return false;
    } finally {
      _isWorking = false;
      notifyListeners();
    }
  }
}
