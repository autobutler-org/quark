import 'package:flutter/foundation.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';

/// Whether the signed-in account's chat identity or vault key lacks a wrap
/// under the recovery phrase, and adding one (#3530).
///
/// Keys made at an ordinary sign-in, or a vault set up without the phrase,
/// would be lost at a recovery. The vault page and the chat page call [check]
/// once their keys are open, show an offer while [offerVault] or [offerChat]
/// says so, and hand what the user types to [add]. The Quark checks the
/// phrase before anything is stored, so a mistyped one changes nothing and
/// comes back as [error].
///
/// The app shares [instance], so the offer one page put away stays away on
/// the other, until a different account signs in.
class RecoveryPhraseController extends ChangeNotifier {
  /// Builds a controller. Every collaborator has a real default; tests pass
  /// fakes.
  RecoveryPhraseController({
    Future<MissingPhraseWraps> Function()? missing,
    Future<void> Function({required String password, required String phrase})?
    addPhrase,
    String? Function()? account,
  }) : _missingFetch = missing ?? AuthService.missingPhraseWraps,
       _addPhrase = addPhrase ?? AuthService.addRecoveryPhrase,
       _account = account ?? (() => AppSettings.instance.username);

  /// The app's controller.
  static final RecoveryPhraseController instance = RecoveryPhraseController();

  final Future<MissingPhraseWraps> Function() _missingFetch;
  final Future<void> Function({
    required String password,
    required String phrase,
  })
  _addPhrase;
  final String? Function() _account;

  MissingPhraseWraps _missing = (chat: false, vault: false);

  /// The account the offer was put away for; null while it is not.
  String? _dismissedFor;

  bool _isBusy = false;
  Object? _error;

  /// Whether the offer was put away for the signed-in account.
  bool get _dismissed => _dismissedFor != null && _dismissedFor == _account();

  /// Whether the vault page should offer to add the phrase.
  bool get offerVault => _missing.vault && !_dismissed;

  /// Whether the chat page should offer to add the phrase.
  bool get offerChat => _missing.chat && !_dismissed;

  /// Whether [add] is running.
  bool get isBusy => _isBusy;

  /// Why the last [add] failed; null when it did not.
  Object? get error => _error;

  /// Asks the Quark which keys have no phrase wrap. A failure leaves the
  /// offer as it was: it is advice, and the next check asks again.
  Future<void> check() async {
    try {
      _missing = await _missingFetch();
    } catch (e) {
      debugPrint('[recovery_phrase_controller.dart] check failed: $e');
      return;
    }
    notifyListeners();
  }

  /// Wraps the keys under [phrase], once [password] has opened them and the
  /// Quark has confirmed the phrase is the account's. Returns whether that
  /// worked; when it did not, [error] says why and nothing changed.
  Future<bool> add({required String password, required String phrase}) async {
    if (_isBusy) return false;
    _isBusy = true;
    _error = null;
    notifyListeners();
    try {
      await _addPhrase(password: password, phrase: phrase);
      _missing = (chat: false, vault: false);
      return true;
    } catch (e) {
      _error = e;
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// Puts the offer away for the signed-in account until the app restarts.
  void dismiss() {
    _dismissedFor = _account();
    notifyListeners();
  }

  /// Forgets the last failure, for a dialog opened afresh.
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
