import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/models/upload_session_summary.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/upload_sessions_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/upload_rate.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The signed-in account's uploads as the Quark sees them, from every device,
/// for the whole app session (#3972).
///
/// One instance, [instance], feeds the System page's Jobs tab and the top
/// bar's jobs badge. The list is fetched again on every
/// `upload_session_changed` event rather than built from events, which are
/// only hints and can be dropped. Fetches that a burst of events asks for
/// collapse into one.
///
/// Service calls arrive as function parameters defaulting to the real static
/// methods, so a test passes fakes without a mocking library.
class UploadSessionsController extends ChangeNotifier {
  /// Creates a controller talking to the real services unless overridden.
  UploadSessionsController({
    Future<UploadSessionList> Function() listSessions =
        UploadSessionsService.listSessions,
    Future<void> Function(String id) cancelSession =
        UploadSessionsService.cancelSession,
    Stream<FileEvent> Function() events = _appEvents,
    ValueListenable<String?> Function() session = _appSession,
    DateTime Function() clock = DateTime.now,
    Duration refetchDelay = const Duration(milliseconds: 300),
  }) : _listSessions = listSessions,
       _cancelSession = cancelSession,
       _events = events,
       _session = session,
       _clock = clock,
       _refetchDelay = refetchDelay;

  /// The app's one controller.
  static final UploadSessionsController instance = UploadSessionsController();

  final Future<UploadSessionList> Function() _listSessions;
  final Future<void> Function(String id) _cancelSession;
  final Stream<FileEvent> Function() _events;
  final ValueListenable<String?> Function() _session;
  final DateTime Function() _clock;
  final Duration _refetchDelay;

  final _rates = UploadRateTracker();
  StreamSubscription<FileEvent>? _subscription;
  ValueListenable<String?>? _sessionToken;
  Timer? _ticker;
  Timer? _refetch;
  int _generation = 0;

  UploadSessionList _sessions = const UploadSessionList();
  bool _isLoading = false;
  String? _error;

  /// Whether a fetch is in flight.
  bool get isLoading => _isLoading;

  /// Copy for the last failed fetch, or null.
  String? get error => _error;

  /// How many uploads are in flight now, from any of the account's devices.
  int get activeCount => _sessions.active.length;

  /// Every upload in flight, oldest first, then the recent ones that ended,
  /// newest first, as the package's list renders them.
  List<UploadItem> get items {
    final now = _clock();
    return [
      for (final session in _sessions.active) _activeItem(session, now),
      for (final session in _sessions.finished) _finishedItem(session),
    ];
  }

  UploadItem _activeItem(UploadSessionSummary session, DateTime now) {
    final rate = _rates.read(
      id: session.sessionId,
      offset: session.offset,
      total: session.totalSize,
      updatedAt: session.updatedAt,
      now: now,
    );
    final committing = session.state == UploadSessionState.committing;
    return UploadItem(
      id: session.sessionId,
      fileName: session.fileName,
      destination: destinationLabel(session),
      status: committing
          ? UploadItemStatus.finishing
          : rate.stalled
          ? UploadItemStatus.stalled
          : UploadItemStatus.uploading,
      sentBytes: session.offset,
      totalBytes: session.totalSize,
      bytesPerSecond: rate.bytesPerSecond,
      remaining: rate.remaining,
      // A commit is already moving the file into place; canceling it
      // would only race the rename.
      canCancel: !committing,
    );
  }

  UploadItem _finishedItem(UploadSessionSummary session) => UploadItem(
    id: session.sessionId,
    fileName: session.fileName,
    destination: destinationLabel(session),
    status: switch (session.state) {
      UploadSessionState.completed => UploadItemStatus.completed,
      UploadSessionState.canceled => UploadItemStatus.canceled,
      UploadSessionState.expired => UploadItemStatus.expired,
      _ => UploadItemStatus.failed,
    },
    sentBytes: session.offset,
    totalBytes: session.totalSize,
  );

  /// Where [session]'s file is going, in words: its folder, and whether it
  /// is on a plugged-in drive.
  static String destinationLabel(UploadSessionSummary session) {
    final folder = session.rootDir.isEmpty ? 'Files' : session.rootDir;
    return session.serial.isEmpty
        ? 'To $folder'
        : 'To $folder on an external drive';
  }

  /// Subscribes to the events stream and the session, loading whenever a user
  /// is signed in so [activeCount] is right before the Jobs tab is opened.
  /// Safe to call more than once.
  void start() {
    if (_subscription != null) return;
    _subscription = _events().listen(_onEvent);
    final session = _sessionToken = _session()..addListener(_onSessionChanged);
    if (session.value != null) unawaited(load());
  }

  /// Signing in loads that user's uploads; signing out forgets them, so the
  /// badge never counts another account's uploads.
  void _onSessionChanged() {
    if (_sessionToken?.value != null) {
      unawaited(load());
      return;
    }
    _generation++;
    _refetch?.cancel();
    _sessions = const UploadSessionList();
    _rates.retain(const {});
    _error = null;
    _isLoading = false;
    _syncTicker();
    notifyListeners();
  }

  /// Fetches the list. Never throws: a failure lands in [error].
  Future<void> load() async {
    final generation = ++_generation;
    _isLoading = true;
    notifyListeners();
    try {
      final sessions = await _listSessions();
      if (generation != _generation) return;
      _sessions = sessions;
      _rates.retain({for (final s in sessions.active) s.sessionId});
      _error = null;
    } catch (e) {
      if (generation != _generation) return;
      debugPrint('[upload_sessions_controller.dart] Failed to list: $e');
      _error = Errors.message(e, 'load your uploads');
    }
    _isLoading = false;
    _syncTicker();
    notifyListeners();
  }

  /// Cancels upload [id] from this device, whichever device is sending it.
  /// Returns copy for a refusal, or null when it worked.
  Future<String?> cancel(String id) async {
    try {
      await _cancelSession(id);
    } catch (e) {
      return Errors.cancelUpload(e);
    }
    await load();
    return null;
  }

  void _onEvent(FileEvent event) {
    if (event.kind != 'upload_session_changed' && event.kind != 'resync') {
      return;
    }
    if (_sessionToken?.value == null) return;
    _refetch?.cancel();
    _refetch = Timer(_refetchDelay, () => unawaited(load()));
  }

  /// Ticks once a second while anything is in flight, so a stalled upload is
  /// called stalled without waiting for an event that will not come.
  void _syncTicker() {
    if (activeCount == 0) {
      _ticker?.cancel();
      _ticker = null;
    } else {
      _ticker ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => notifyListeners(),
      );
    }
  }

  @override
  void dispose() {
    _generation++;
    _subscription?.cancel();
    _sessionToken?.removeListener(_onSessionChanged);
    _ticker?.cancel();
    _refetch?.cancel();
    super.dispose();
  }

  static ValueListenable<String?> _appSession() =>
      AppSettings.instance.sessionTokenNotifier;

  static Stream<FileEvent> _appEvents() {
    EventsService.instance.start();
    return EventsService.instance.events;
  }
}
