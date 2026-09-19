import 'package:flutter/foundation.dart';
import 'package:quark/services/auth_service.dart';

typedef RequestAccountFn =
    Future<String> Function({
      required String username,
      required String password,
    });

/// Where the request-account flow is.
enum RequestAccountStep {
  /// Choosing a username and password.
  form,

  /// The request went in; the recovery phrase is on screen until acknowledged.
  phrase,

  /// Done: waiting for an admin to approve it.
  sent,
}

/// State behind the request-account page (#1908): the form, then the
/// recovery phrase, then a "request sent" state.
///
/// The request call arrives as a parameter defaulting to
/// [AuthService.requestAccount], so a test passes a fake. Failures stay raw;
/// the page turns them into a sentence with `Errors`.
class RequestAccountController extends ChangeNotifier {
  RequestAccountController({
    RequestAccountFn requestAccount = AuthService.requestAccount,
  }) : _requestAccount = requestAccount;

  final RequestAccountFn _requestAccount;

  RequestAccountStep _step = RequestAccountStep.form;
  bool _isSubmitting = false;
  Object? _error;
  String? _recoveryPhrase;
  bool _acknowledged = false;
  bool _disposed = false;

  RequestAccountStep get step => _step;

  /// Whether the request is in flight.
  bool get isSubmitting => _isSubmitting;

  /// Why the last request failed, or null.
  Object? get error => _error;

  /// The phrase the Quark returned for the new account. Shown once.
  String? get recoveryPhrase => _recoveryPhrase;

  /// Whether the user has confirmed they saved [recoveryPhrase].
  bool get acknowledged => _acknowledged;

  /// Sends the request. Ignored while one is already in flight.
  Future<void> submit({
    required String username,
    required String password,
  }) async {
    if (_isSubmitting) return;
    _isSubmitting = true;
    _error = null;
    notifyListeners();
    try {
      final phrase = await _requestAccount(
        username: username,
        password: password,
      );
      if (_disposed) return;
      _recoveryPhrase = phrase;
      _step = RequestAccountStep.phrase;
    } catch (error) {
      if (_disposed) return;
      _error = error;
    } finally {
      if (!_disposed) {
        _isSubmitting = false;
        notifyListeners();
      }
    }
  }

  /// Records whether the phrase has been saved.
  void setAcknowledged(bool value) {
    if (_acknowledged == value) return;
    _acknowledged = value;
    notifyListeners();
  }

  /// Leaves the phrase step, once it has been acknowledged.
  void finish() {
    if (_step != RequestAccountStep.phrase || !_acknowledged) return;
    _step = RequestAccountStep.sent;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
