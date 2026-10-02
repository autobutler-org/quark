import 'package:flutter/foundation.dart';
import 'package:quark/models/auth_session.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/sessions_service.dart';
import 'package:quark/utils/error_text.dart';

/// The Sessions section of the Account tab (#1663): the account's signed-in
/// sessions, and signing them out.
///
/// Service calls arrive as function parameters defaulting to the real static
/// methods, so a test passes fakes without a mocking library.
class SessionsController extends ChangeNotifier {
  /// Creates a controller talking to the real [SessionsService] and
  /// [AuthService.logout] unless overridden.
  SessionsController({
    Future<List<AuthSession>> Function() list = SessionsService.list,
    Future<void> Function(String id) revoke = SessionsService.revoke,
    Future<void> Function() revokeOthers = SessionsService.revokeOthers,
    Future<void> Function() logout = AuthService.logout,
  }) : _list = list,
       _revoke = revoke,
       _revokeOthers = revokeOthers,
       _logout = logout;

  final Future<List<AuthSession>> Function() _list;
  final Future<void> Function(String id) _revoke;
  final Future<void> Function() _revokeOthers;
  final Future<void> Function() _logout;

  List<AuthSession> _sessions = const [];
  bool _isLoading = false;
  bool _isWorking = false;
  String? _error;
  bool _disposed = false;

  /// The sessions the Quark last listed; empty before the first load.
  List<AuthSession> get sessions => _sessions;

  /// Whether the list is being fetched.
  bool get isLoading => _isLoading;

  /// Whether a sign-out is in flight. The section disables its controls.
  bool get isWorking => _isWorking;

  /// User-facing copy for the last failure, or null. Always from [Errors].
  String? get error => _error;

  /// Whether there is a session other than the one in use to sign out.
  bool get hasOthers => _sessions.any((session) => !session.current);

  /// Fetches the list.
  Future<void> load() async {
    _isLoading = true;
    _notify();
    try {
      _sessions = await _list();
      _error = null;
    } catch (error) {
      _error = Errors.message(error, 'load your sessions');
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  /// Signs [session] out. True on success.
  ///
  /// The session in use is signed out the way Sign out does it, through
  /// logout, so the app forgets its token as the Quark forgets the session.
  /// The caller then leaves the page.
  Future<bool> revoke(AuthSession session) => _change(
    () => session.current ? _logout() : _revoke(session.id),
    'sign out that session',
    reload: !session.current,
  );

  /// Signs out every session but the one in use. True on success.
  Future<bool> revokeOthers() =>
      _change(_revokeOthers, 'sign out your other sessions');

  /// Runs [request], then reloads the list unless the app just signed out.
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
      if (reload) _sessions = await _list();
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
