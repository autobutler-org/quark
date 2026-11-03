import 'package:flutter/foundation.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';

/// The new-recovery-phrase dialog's one service call, kept out of the
/// Settings page (#3183).
///
/// The page owns the dialog and closes it; this owns the request, what the
/// dialog shows while it runs and after it fails, and the new [phrase] once
/// it has gone through.
///
/// The service call arrives as a function parameter defaulting to the real
/// static method, so a test passes a fake without a mocking library.
class NewRecoveryPhraseController extends ChangeNotifier with SafeNotifier {
  /// Creates a controller talking to the real [AuthService] unless overridden.
  NewRecoveryPhraseController({
    Future<String> Function({required String password}) rotateRequest =
        AuthService.rotateRecoveryPhrase,
  }) : _rotateRequest = rotateRequest;

  final Future<String> Function({required String password}) _rotateRequest;

  bool _isWorking = false;
  String? _error;
  String? _phrase;

  /// Whether a rotation is in flight. The dialog disables its field and
  /// buttons meanwhile.
  bool get isWorking => _isWorking;

  /// User-facing copy for the last failure, or null. Always from [Errors].
  String? get error => _error;

  /// The new phrase, to show once, or null until the Quark has taken it.
  String? get phrase => _phrase;

  /// Gives the account a new recovery phrase, confirmed with [password].
  /// On failure [error] says why. A second call while one is in flight does
  /// nothing.
  Future<void> rotate(String password) async {
    if (_isWorking) return;
    _isWorking = true;
    _error = null;
    notifyListeners();
    try {
      _phrase = await _rotateRequest(password: password);
    } catch (error) {
      _error = Errors.message(error, 'make a new recovery phrase');
    } finally {
      _isWorking = false;
      notifyListeners();
    }
  }
}
