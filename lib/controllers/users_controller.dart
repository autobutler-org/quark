import 'package:flutter/foundation.dart';
import 'package:quark/models/user_account.dart';
import 'package:quark/services/users_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

typedef ListUsersFn = Future<List<UserAccount>> Function();
typedef AccountActionFn = Future<void> Function(String username);
typedef ReadAccessRequestsFn = Future<bool> Function();
typedef SetAccessRequestsFn = Future<bool> Function(bool enabled);

/// State behind the Users page (#1662): the accounts and pending requests on
/// the Quark, whether it takes requests, and the admin actions on one account
/// at a time.
///
/// Service calls arrive as function parameters defaulting to [UsersService],
/// so a test passes fakes without a mocking library. Actions hand back the
/// raw failure rather than copy; the page turns it into a sentence with
/// `Errors`.
class UsersController extends ChangeNotifier {
  UsersController({
    this.selfUsername,
    ListUsersFn listUsers = UsersService.list,
    AccountActionFn promoteUser = UsersService.promote,
    AccountActionFn demoteUser = UsersService.demote,
    AccountActionFn approveRequest = UsersService.approve,
    AccountActionFn denyRequest = UsersService.deny,
    ReadAccessRequestsFn readAccessRequests =
        UsersService.accessRequestsEnabled,
    SetAccessRequestsFn setAccessRequests =
        UsersService.setAccessRequestsEnabled,
  }) : _listUsers = listUsers,
       _promoteUser = promoteUser,
       _demoteUser = demoteUser,
       _approveRequest = approveRequest,
       _denyRequest = denyRequest,
       _readAccessRequests = readAccessRequests,
       _setAccessRequests = setAccessRequests;

  /// The signed-in account, which the list offers no actions on.
  final String? selfUsername;

  final ListUsersFn _listUsers;
  final AccountActionFn _promoteUser;
  final AccountActionFn _demoteUser;
  final AccountActionFn _approveRequest;
  final AccountActionFn _denyRequest;
  final ReadAccessRequestsFn _readAccessRequests;
  final SetAccessRequestsFn _setAccessRequests;

  List<UserAccount> _users = const [];
  bool? _accessRequestsEnabled;
  bool _isSavingAccessRequests = false;
  bool _hasLoaded = false;
  bool _isLoading = false;
  Object? _error;
  final Set<String> _busy = {};

  /// Bumped by every load, so a slow response cannot overwrite a newer one.
  int _generation = 0;
  bool _disposed = false;

  /// Every account that is not a pending request, for the accounts list.
  List<UserAccountItem> get accounts => [
    for (final user in _users)
      if (user.status != UserAccount.pending) itemFor(user),
  ];

  /// Requests waiting for an admin.
  List<UserAccountItem> get pending => [
    for (final user in _users)
      if (user.status == UserAccount.pending) itemFor(user),
  ];

  /// Whether the Quark takes account requests. Null until the first load.
  bool? get accessRequestsEnabled => _accessRequestsEnabled;

  /// Whether a change to [accessRequestsEnabled] is being saved.
  bool get isSavingAccessRequests => _isSavingAccessRequests;

  /// Whether a load is in flight.
  bool get isLoading => _isLoading;

  /// Whether any load has succeeded, so a refresh keeps the rows showing.
  bool get hasLoaded => _hasLoaded;

  /// Why the last load failed, or null. Raw; the page composes the copy.
  Object? get error => _error;

  /// Accounts with an action in flight.
  Set<String> get busyUsernames => Set.unmodifiable(_busy);

  /// The package's view of [user].
  static UserAccountItem itemFor(UserAccount user) => UserAccountItem(
    username: user.username,
    isAdmin: user.isAdmin,
    status: switch (user.status) {
      UserAccount.pending => UserAccountStatus.pending,
      UserAccount.disabled => UserAccountStatus.disabled,
      _ => UserAccountStatus.active,
    },
  );

  /// Fetches the accounts and the access-requests setting. A newer load
  /// supersedes this one.
  Future<void> load() async {
    final generation = ++_generation;
    _isLoading = true;
    _notify();
    try {
      final results = await Future.wait<Object>([
        _listUsers(),
        _readAccessRequests(),
      ]);
      if (!_isCurrent(generation)) return;
      _users = results[0] as List<UserAccount>;
      _accessRequestsEnabled = results[1] as bool;
      _error = null;
      _hasLoaded = true;
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _error = error;
    } finally {
      if (_isCurrent(generation)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Makes [username] an admin. Null on success, otherwise the failure.
  Future<Object?> promote(String username) =>
      _act(username, () => _promoteUser(username));

  /// Stops [username] being an admin. Null on success, otherwise the failure.
  Future<Object?> demote(String username) =>
      _act(username, () => _demoteUser(username));

  /// Approves the request from [username]. Null on success, otherwise the
  /// failure.
  Future<Object?> approve(String username) =>
      _act(username, () => _approveRequest(username));

  /// Denies the request from [username]. Null on success, otherwise the
  /// failure.
  Future<Object?> deny(String username) =>
      _act(username, () => _denyRequest(username));

  /// Turns account requests on or off. Null on success, otherwise the
  /// failure, in which case the setting is left as it was.
  Future<Object?> setAccessRequestsEnabled(bool enabled) async {
    if (_isSavingAccessRequests) return null;
    _isSavingAccessRequests = true;
    _notify();
    try {
      final saved = await _setAccessRequests(enabled);
      if (!_disposed) _accessRequestsEnabled = saved;
      return null;
    } catch (error) {
      return error;
    } finally {
      _isSavingAccessRequests = false;
      _notify();
    }
  }

  /// Runs [request] for [username], one action per account at a time, and
  /// reloads when it worked.
  Future<Object?> _act(String username, Future<void> Function() request) async {
    if (_busy.contains(username)) return null;
    _busy.add(username);
    _notify();
    try {
      await request();
      await load();
      return null;
    } catch (error) {
      return error;
    } finally {
      _busy.remove(username);
      _notify();
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
