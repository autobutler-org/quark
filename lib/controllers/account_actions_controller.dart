import 'package:flutter/foundation.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/settings/reset_quark_dialog.dart';

/// The destructive account actions on the account and data page, kept out of
/// its [State] (#1762, #2346).
///
/// Narrow on purpose: it owns the one thing the page must not do for itself,
/// which is call a service. The page still owns its dialogs and its
/// navigation.
///
/// Service calls arrive as function parameters defaulting to the real static
/// methods, so a test passes fakes without a mocking library.
class AccountActionsController extends ChangeNotifier {
  /// Creates a controller talking to the real [AuthService] unless overridden.
  AccountActionsController({
    Future<DeleteAccountResult> Function({required String password})
        deleteAccountRequest =
        AuthService.deleteAccount,
    Future<DeleteAccountResult> Function({
          required String password,
          required bool database,
          required bool files,
          required bool devices,
        })
        resetQuarkRequest =
        AuthService.resetQuark,
    Future<String> Function() signedOutDestination =
        destinationForSignedOutUser,
  }) : _deleteAccountRequest = deleteAccountRequest,
       _resetQuarkRequest = resetQuarkRequest,
       _signedOutDestination = signedOutDestination;

  final Future<DeleteAccountResult> Function({required String password})
  _deleteAccountRequest;
  final Future<DeleteAccountResult> Function({
    required String password,
    required bool database,
    required bool files,
    required bool devices,
  })
  _resetQuarkRequest;
  final Future<String> Function() _signedOutDestination;

  bool _isWorking = false;
  String? _error;
  bool _filesRetained = false;

  /// Whether a deletion or reset is in flight. The page disables its entries
  /// meanwhile.
  bool get isWorking => _isWorking;

  /// User-facing copy for the last failure, or null. Always from [Errors].
  String? get error => _error;

  /// Whether the last successful call left stored files on the Quark.
  ///
  /// The Quark reports this rather than the app deriving it, so one place
  /// decides what counts as data left behind. The page says so on the way out.
  bool get filesRetained => _filesRetained;

  /// The account the deletion dialog should name, or null when this session
  /// never named one (it was recovered by phrase, or predates the app
  /// recording it). Only used for copy: the password is the confirmation.
  String? get username => AppSettings.instance.username;

  /// Deletes the signed-in account, and nothing else.
  ///
  /// Returns the route the caller should send the user to, or null when it
  /// failed and [error] now says why. Success revokes the session on the
  /// Quark, so there is always somewhere to go: setup when this was the last
  /// account on the appliance, login otherwise.
  Future<String?> deleteAccount({required String password}) => _run(
    () => _deleteAccountRequest(password: password),
    'delete your account',
  );

  /// Factory-resets the Quark, wiping the aspects [selection] names.
  ///
  /// Same contract as [deleteAccount]: a route on success, null on failure.
  Future<String?> resetQuark({
    required QuarkResetSelection selection,
    required String password,
  }) => _run(
    () => _resetQuarkRequest(
      password: password,
      database: selection.database,
      files: selection.files,
      devices: selection.devices,
    ),
    'reset your Quark',
  );

  /// Runs [request], publishes the outcome, and answers with where to go next.
  ///
  /// [action] names what was being attempted, for [Errors.message].
  Future<String?> _run(
    Future<DeleteAccountResult> Function() request,
    String action,
  ) async {
    _isWorking = true;
    _error = null;
    notifyListeners();
    try {
      _filesRetained = (await request()).filesRetained;
      return await _signedOutDestination();
    } on UnauthorizedException {
      // The session was already gone. Whatever was asked for may or may not
      // have happened, but either way this user cannot act on this Quark any
      // more, so they get routed out rather than shown a failure they cannot
      // do anything about.
      _filesRetained = false;
      return await _signedOutDestination();
    } catch (error) {
      _error = Errors.message(error, action);
      return null;
    } finally {
      _isWorking = false;
      notifyListeners();
    }
  }
}
