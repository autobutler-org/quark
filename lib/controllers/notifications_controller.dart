import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:quark/models/app_notification.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/notifications_service.dart';
import 'package:quark/utils/error_text.dart';

/// The signed-in account's notifications and which types it turned off, for
/// the whole app session (#2493).
///
/// One instance, [instance], feeds the top bar's bell, the list it opens and
/// the switches in Settings. The Quark derives the list on each request and
/// announces no notification event, so the list is fetched again when the
/// session changes, when a `backup_completed`, `account_changed` or `resync`
/// event arrives, when the app comes back to the foreground, and after a
/// switch is saved.
///
/// Service calls arrive as function parameters defaulting to the real static
/// methods, so a test passes fakes without a mocking library.
class NotificationsController extends ChangeNotifier {
  /// Creates a controller talking to the real services unless overridden.
  NotificationsController({
    Future<List<AppNotification>> Function() listNotifications =
        NotificationsService.list,
    Future<Set<String>> Function() readDisabled =
        NotificationsService.disabledTypes,
    Future<Set<String>> Function(NotificationType type, bool enabled)
        saveEnabled =
        NotificationsService.setEnabled,
    Stream<FileEvent> Function() events = _appEvents,
    ValueListenable<String?> Function() session = _appSession,
  }) : _listNotifications = listNotifications,
       _readDisabled = readDisabled,
       _saveEnabled = saveEnabled,
       _events = events,
       _session = session;

  /// The app's one controller.
  static final NotificationsController instance = NotificationsController();

  final Future<List<AppNotification>> Function() _listNotifications;
  final Future<Set<String>> Function() _readDisabled;
  final Future<Set<String>> Function(NotificationType type, bool enabled)
  _saveEnabled;
  final Stream<FileEvent> Function() _events;
  final ValueListenable<String?> Function() _session;

  StreamSubscription<FileEvent>? _subscription;
  ValueListenable<String?>? _sessionToken;
  AppLifecycleListener? _lifecycle;

  /// Bumped by every [load] and by a session change, so a slower, older
  /// answer is dropped.
  int _generation = 0;

  /// Bumped by a session change only, so a preferences answer for the
  /// previous account is dropped.
  int _account = 0;

  List<AppNotification> _notifications = const [];
  bool _hasLoaded = false;
  bool _isLoading = false;
  String? _error;

  Set<String> _disabled = const {};
  bool _preferencesLoaded = false;
  bool _isLoadingPreferences = false;
  bool _isSaving = false;
  String? _preferencesError;

  /// The account's current notifications.
  List<AppNotification> get notifications => _notifications;

  /// Whether [notifications] has been fetched for this session, so an empty
  /// list means there are none rather than that nobody has asked yet.
  bool get hasLoaded => _hasLoaded;

  /// Whether a fetch of [notifications] is in flight.
  bool get isLoading => _isLoading;

  /// Copy for the last failed fetch of [notifications], or null.
  String? get error => _error;

  /// Whether a user is signed in. False before [start].
  bool get isSignedIn => _sessionToken?.value != null;

  /// Whether [isEnabled] reflects what the Quark holds, which it does once
  /// [loadPreferences] has answered for this account.
  bool get preferencesLoaded => _preferencesLoaded;

  /// Whether [loadPreferences] is in flight.
  bool get isLoadingPreferences => _isLoadingPreferences;

  /// Whether [setEnabled] is saving. One save runs at a time, since each one
  /// reads the settings and writes them back whole.
  bool get isSaving => _isSaving;

  /// Copy for the last failed [loadPreferences] or [setEnabled], or null.
  String? get preferencesError => _preferencesError;

  /// Whether the account receives notifications of [type].
  bool isEnabled(NotificationType type) => !_disabled.contains(type.wire);

  /// Subscribes to the events stream, the session and the app's lifecycle,
  /// loading whenever a user is signed in so the bell's count is right before
  /// it is opened. Safe to call more than once.
  void start() {
    if (_subscription != null) return;
    _subscription = _events().listen(_onEvent);
    _lifecycle = AppLifecycleListener(onResume: _refetch);
    final session = _sessionToken = _session()..addListener(_onSessionChanged);
    if (session.value != null) unawaited(load());
  }

  /// Signing in (or in as someone else) loads that account's notifications;
  /// signing out forgets them and the switches, so nothing of another
  /// session's shows.
  void _onSessionChanged() {
    _account++;
    _disabled = const {};
    _preferencesLoaded = false;
    _isLoadingPreferences = false;
    _isSaving = false;
    _preferencesError = null;
    _notifications = const [];
    _hasLoaded = false;
    _error = null;
    if (isSignedIn) {
      unawaited(load());
      return;
    }
    _generation++;
    _isLoading = false;
    notifyListeners();
  }

  void _onEvent(FileEvent event) {
    // A completed backup clears the backup reminders. An account change can
    // make this user an admin or stop them being one, and only admins get
    // them. A resync means the socket dropped events.
    if (const {
      'backup_completed',
      'account_changed',
      'resync',
    }.contains(event.kind)) {
      _refetch();
    }
  }

  void _refetch() {
    if (isSignedIn) unawaited(load());
  }

  /// Fetches [notifications]. Never throws: a failure lands in [error] and
  /// keeps the list already shown.
  Future<void> load() async {
    final generation = ++_generation;
    _isLoading = true;
    notifyListeners();
    try {
      final notifications = await _listNotifications();
      if (generation != _generation) return;
      _notifications = notifications;
      _hasLoaded = true;
      _error = null;
    } catch (e) {
      if (generation != _generation) return;
      debugPrint('[notifications_controller.dart] Failed to list: $e');
      _error = Errors.message(e, 'load your notifications');
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Fetches which types the account turned off. Never throws: a failure
  /// lands in [preferencesError].
  Future<void> loadPreferences() async {
    final account = _account;
    _isLoadingPreferences = true;
    _preferencesError = null;
    notifyListeners();
    try {
      final disabled = await _readDisabled();
      if (account != _account) return;
      _disabled = disabled;
      _preferencesLoaded = true;
    } catch (e) {
      if (account != _account) return;
      debugPrint('[notifications_controller.dart] Failed to read prefs: $e');
      _preferencesError = Errors.message(e, 'load your notification settings');
    }
    _isLoadingPreferences = false;
    notifyListeners();
  }

  /// Turns [type] on or off for the account: flips it at once, saves it, and
  /// puts it back with [preferencesError] set if the Quark refuses. A saved
  /// change fetches [notifications] again, since the Quark leaves out a type
  /// that is off. Does nothing while another save [isSaving].
  Future<void> setEnabled(NotificationType type, bool enabled) async {
    if (_isSaving || isEnabled(type) == enabled) return;
    final account = _account;
    final before = _disabled;
    _disabled = enabled
        ? before.difference({type.wire})
        : {...before, type.wire};
    _isSaving = true;
    _preferencesError = null;
    notifyListeners();
    var saved = false;
    try {
      final disabled = await _saveEnabled(type, enabled);
      if (account != _account) return;
      _disabled = disabled;
      saved = true;
    } catch (e) {
      if (account != _account) return;
      debugPrint('[notifications_controller.dart] Failed to save prefs: $e');
      _disabled = before;
      _preferencesError = Errors.message(e, 'save the setting');
    }
    _isSaving = false;
    notifyListeners();
    if (saved) await load();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _sessionToken?.removeListener(_onSessionChanged);
    _lifecycle?.dispose();
    super.dispose();
  }

  static ValueListenable<String?> _appSession() =>
      AppSettings.instance.sessionTokenNotifier;

  static Stream<FileEvent> _appEvents() {
    EventsService.instance.start();
    return EventsService.instance.events;
  }
}
