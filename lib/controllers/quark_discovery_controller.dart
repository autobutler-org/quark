import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/quark_discovery.dart';

/// State behind the list of Quarks found on the local network (#2312).
///
/// Browses from construction until [dispose], which stops the browse. The
/// browser arrives as a parameter so a test passes a fake stream. Failures
/// stay raw; the widget turns them into a sentence with `Errors`.
class QuarkDiscoveryController extends ChangeNotifier {
  QuarkDiscoveryController({
    required QuarkBrowser browse,
    Duration searchWindow = const Duration(seconds: 5),
  }) {
    _subscription = browse().listen(
      (quarks) {
        _quarks = quarks;
        notifyListeners();
      },
      onError: (Object error) {
        _error = error;
        _isSearching = false;
        notifyListeners();
      },
    );
    _searchTimer = Timer(searchWindow, () {
      _isSearching = false;
      notifyListeners();
    });
  }

  late final StreamSubscription<List<HostEntry>> _subscription;
  late final Timer _searchTimer;

  List<HostEntry> _quarks = const [];
  bool _isSearching = true;
  Object? _error;

  /// The Quarks found so far.
  List<HostEntry> get quarks => _quarks;

  /// True until the search window passes or the browse fails. The browse
  /// keeps going after that; this only decides when an empty list stops
  /// reading as "still looking" and starts reading as "none found".
  bool get isSearching => _isSearching;

  /// Why the browse failed, or null.
  Object? get error => _error;

  @override
  void dispose() {
    _searchTimer.cancel();
    _subscription.cancel();
    super.dispose();
  }
}
