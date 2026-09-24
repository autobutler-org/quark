import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:quark/services/app_settings.dart';

/// Adds auto-refresh and non-disruptive loading state to a [State].
///
/// Usage:
/// ```dart
/// class _MyPageState extends State<MyPage>
///     with AutoRefreshMixin {
///
///   @override
///   Duration get refreshInterval => const Duration(seconds: 30);
///
///   @override
///   Future<void> refresh() async {
///     // fetch data; update state inside here
///   }
/// }
/// ```
///
/// In the widget tree, use [isInitialLoad] for full-screen spinners and
/// [isRefreshing] for the in-progress indicator on the refresh button.
mixin AutoRefreshMixin<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  // ── State ──────────────────────────────────────────────────────────────────

  /// True only for the very first load (no data yet).
  bool isInitialLoad = true;

  /// True while a refresh (initial or subsequent) is in flight.
  bool isRefreshing = false;

  Timer? _refreshTimer;
  bool _refreshInFlight = false;
  DateTime? _lastRefreshStarted;

  // ── Overrides ──────────────────────────────────────────────────────────────

  /// How often to auto-refresh. Reads from [AppSettings.refreshIntervalSeconds]
  /// by default. Override to use a fixed interval regardless of settings.
  /// Return null or [Duration.zero] to disable auto-refresh.
  Duration? get refreshInterval {
    final seconds = AppSettings.instance.refreshIntervalSeconds;
    return seconds > 0 ? Duration(seconds: seconds) : null;
  }

  /// Perform the data fetch. Called on initial load and on each auto-refresh.
  /// Update your widget state inside this method.
  Future<void> refresh();

  /// How long a refresh may be in flight before another is allowed to start.
  ///
  /// Not a request timeout — the earlier fetch carries on, it just stops
  /// holding the door shut. Without this a single request that never returns
  /// leaves [_refreshInFlight] true and every later refresh, the reload button
  /// included, returns immediately for the rest of the session. A saturated
  /// connection pool reaches that easily, which a large upload creates.
  Duration get refreshTimeout => const Duration(seconds: 30);

  /// Called right after [isRefreshing] changes, for a parent that shows it
  /// where this State does not build, such as the app bar of the page a tab
  /// sits in. It can run from [initState], mid-build, so an override that
  /// sets another widget's state has to wait for the frame.
  void didChangeRefreshing() {}

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _triggerRefresh(initial: true);
    _startTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      _triggerRefresh();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _refreshTimer?.cancel();
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Call from a manual refresh button. Same guard as the timer.
  Future<void> manualRefresh() => _triggerRefresh();

  // ── Internals ──────────────────────────────────────────────────────────────

  void _startTimer() {
    _refreshTimer?.cancel();
    final interval = refreshInterval;
    if (interval == null || interval == Duration.zero) return;
    _refreshTimer = Timer.periodic(interval, (_) => _triggerRefresh());
  }

  Future<void> _triggerRefresh({bool initial = false}) async {
    final now = DateTime.now();
    final startedAt = _lastRefreshStarted;

    if (_refreshInFlight) {
      // Let one through if the refresh holding the flag has been "in flight"
      // implausibly long. A fetch with no timeout can hang indefinitely — a
      // listing queued behind a large upload will — and without this the flag
      // never clears and refreshing is dead for the rest of the session. The
      // stale one is left to finish or not; whichever resolves last simply
      // clears the flag.
      if (startedAt == null || now.difference(startedAt) < refreshTimeout) {
        return;
      }
      debugPrint(
        '[auto_refresh_mixin.dart] previous refresh still in flight after '
        '$refreshTimeout; starting another rather than staying wedged',
      );
    } else if (!initial &&
        startedAt != null &&
        now.difference(startedAt) < const Duration(seconds: 1)) {
      // Debounce: suppress calls that arrive within 1s of a refresh that has
      // already started (e.g. lifecycle resume + timer firing simultaneously).
      // This prevents the duplicate /storage/devices/status calls seen in #1022.
      return;
    }

    _refreshInFlight = true;
    _lastRefreshStarted = now;
    if (mounted) {
      setState(() => isRefreshing = true);
      didChangeRefreshing();
    }
    try {
      await refresh();
    } catch (e) {
      // A refresh that failed is not a reason to stop refreshing.
      debugPrint('[auto_refresh_mixin.dart] refresh() failed: $e');
    } finally {
      _refreshInFlight = false;
      if (mounted) {
        setState(() {
          isRefreshing = false;
          if (initial) isInitialLoad = false;
        });
        didChangeRefreshing();
      }
    }
  }
}
