import 'package:flutter/foundation.dart';
import 'package:quark/models/user_account.dart';
import 'package:quark/services/users_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

typedef ListUsersFn = Future<List<UserAccount>> Function();
typedef AccountActionFn = Future<void> Function(String username);

/// State behind the Users page (#1662): the accounts on the Quark, the load,
/// and the admin actions on one account at a time.
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
  }) : _listUsers = listUsers,
       _promoteUser = promoteUser,
       _demoteUser = demoteUser;

  /// The signed-in account, which the list offers no actions on.
  final String? selfUsername;

  final ListUsersFn _listUsers;
  final AccountActionFn _promoteUser;
  final AccountActionFn _demoteUser;

  List<UserAccount> _users = const [];
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

  /// Fetches the accounts. A newer load supersedes this one.
  Future<void> load() async {
    final generation = ++_generation;
    _isLoading = true;
    _notify();
    try {
      final users = await _listUsers();
      if (!_isCurrent(generation)) return;
      _users = users;
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
