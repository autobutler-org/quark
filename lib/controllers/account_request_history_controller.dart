import 'package:flutter/foundation.dart';
import 'package:quark/models/account_request_decision.dart';
import 'package:quark/services/account_request_history_service.dart';

typedef ListAccountRequestHistoryFn =
    Future<List<AccountRequestDecision>> Function();

/// State behind the Recent decisions section of the Users page (#2730): the
/// account requests admins approved or denied, newest first.
///
/// The service call arrives as a function parameter defaulting to
/// [AccountRequestHistoryService], so a test passes a fake without a mocking
/// library. A failure comes back raw; the page turns it into a sentence with
/// `Errors`.
class AccountRequestHistoryController extends ChangeNotifier {
  AccountRequestHistoryController({
    ListAccountRequestHistoryFn listHistory = AccountRequestHistoryService.list,
  }) : _listHistory = listHistory;

  final ListAccountRequestHistoryFn _listHistory;

  List<AccountRequestDecision> _decisions = const [];
  bool _hasLoaded = false;
  bool _isLoading = false;
  Object? _error;

  /// Bumped by every load, so a slow response cannot overwrite a newer one.
  int _generation = 0;
  bool _disposed = false;

  /// The decisions, newest first.
  List<AccountRequestDecision> get decisions => _decisions;

  /// Whether a load is in flight.
  bool get isLoading => _isLoading;

  /// Whether any load has succeeded, so a refresh keeps the rows showing.
  bool get hasLoaded => _hasLoaded;

  /// Why the last load failed, or null. Raw; the page composes the copy.
  Object? get error => _error;

  /// Fetches the decisions. A newer load supersedes this one.
  Future<void> load() async {
    final generation = ++_generation;
    _isLoading = true;
    if (!_disposed) notifyListeners();
    try {
      final decisions = await _listHistory();
      if (!_isCurrent(generation)) return;
      _decisions = decisions;
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

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
