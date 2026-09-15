import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/models/job.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/jobs_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What to tell the user when a job finishes: a sentence, and optionally an
/// action that opens [route].
@immutable
class JobAnnouncement {
  /// Creates an announcement.
  const JobAnnouncement(this.message, {this.actionLabel, this.route});

  /// The snack bar's text.
  final String message;

  /// The action's label, or null for no action.
  final String? actionLabel;

  /// Where the action goes. Null exactly when [actionLabel] is.
  final String? route;
}

/// The jobs on the Quark, for the whole app session.
///
/// One instance, [instance], feeds the Jobs page and the finish announcements,
/// so both read the same list and a single events subscription. The list is
/// fetched again on every terminal `job_*` event rather than trusted to the
/// event stream, which drops events when a subscriber lags.
///
/// Service calls arrive as function parameters defaulting to the real static
/// methods, so a test passes fakes without a mocking library.
class JobsController extends ChangeNotifier {
  /// Creates a controller talking to the real services unless overridden.
  JobsController({
    Future<List<Job>> Function({required List<String> kinds}) listJobs =
        JobsService.listJobs,
    Future<Job> Function(int id) cancelJob = JobsService.cancelJob,
    Future<void> Function(int id) retryJob = JobsService.retryJob,
    Stream<FileEvent> Function() events = _appEvents,
    ValueListenable<String?> Function() session = _appSession,
    DateTime Function() clock = DateTime.now,
  }) : _listJobs = listJobs,
       _cancelJob = cancelJob,
       _retryJob = retryJob,
       _events = events,
       _session = session,
       _clock = clock;

  /// The app's one controller.
  static final JobsController instance = JobsController();

  final Future<List<Job>> Function({required List<String> kinds}) _listJobs;
  final Future<Job> Function(int id) _cancelJob;
  final Future<void> Function(int id) _retryJob;
  final Stream<FileEvent> Function() _events;
  final ValueListenable<String?> Function() _session;
  final DateTime Function() _clock;

  final _announcements = StreamController<JobAnnouncement>.broadcast();
  StreamSubscription<FileEvent>? _subscription;
  ValueListenable<String?>? _sessionToken;
  Timer? _ticker;
  int _generation = 0;

  List<Job> _jobs = const [];
  bool _isLoading = false;
  String? _error;

  /// Every job of a kind in [JobKinds], newest first.
  List<Job> get jobs => _jobs;

  /// Whether a fetch is in flight.
  bool get isLoading => _isLoading;

  /// Copy for the last failed fetch, or null.
  String? get error => _error;

  /// How many jobs are running now.
  int get runningCount =>
      _jobs.where((j) => j.status == JobStatus.running).length;

  /// [jobs] as the package's list renders them, with elapsed time as of now.
  List<JobItem> get items => [
    for (final job in _jobs)
      JobItem(
        id: job.id,
        name: job.name,
        status: switch (job.status) {
          JobStatus.pending => JobItemStatus.pending,
          JobStatus.running => JobItemStatus.running,
          JobStatus.completed => JobItemStatus.completed,
          JobStatus.failed => JobItemStatus.failed,
          JobStatus.canceled => JobItemStatus.canceled,
          JobStatus.unknown => JobItemStatus.unknown,
        },
        progress: job.progress,
        attempts: job.attempts,
        elapsed: switch (job.startedAt) {
          null => null,
          final started => (job.finishedAt ?? _clock()).difference(started),
        },
        isQuickCopy: job.lane == 'copy',
        canCancel:
            job.status == JobStatus.pending || job.status == JobStatus.running,
        canRetry: job.status == JobStatus.failed,
      ),
  ];

  /// What to say when a job completes or fails, on whatever page is open.
  Stream<JobAnnouncement> get announcements => _announcements.stream;

  /// Subscribes to the events stream and the session, loading whenever a user
  /// is signed in so [runningCount] is right before the Jobs page is opened.
  /// Safe to call more than once.
  void start() {
    if (_subscription != null) return;
    _subscription = _events().listen(_onEvent);
    final session = _sessionToken = _session()..addListener(_onSessionChanged);
    if (session.value != null) unawaited(load());
  }

  /// Signing in (or in as someone else) loads that user's jobs; signing out
  /// forgets them, so the badge never shows another session's count.
  void _onSessionChanged() {
    if (_sessionToken?.value != null) {
      unawaited(load());
      return;
    }
    _generation++;
    _jobs = const [];
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
      final jobs = await _listJobs(kinds: JobKinds.all);
      if (generation != _generation) return;
      _jobs = jobs;
      _error = null;
    } catch (e) {
      if (generation != _generation) return;
      debugPrint('[jobs_controller.dart] Failed to list jobs: $e');
      _error = Errors.message(e, 'load your jobs');
    }
    _isLoading = false;
    _syncTicker();
    notifyListeners();
  }

  /// Cancels job [id]. Returns copy for a refusal, or null when it worked.
  Future<String?> cancel(int id) async {
    try {
      _apply(await _cancelJob(id));
      notifyListeners();
      return null;
    } catch (e) {
      return Errors.cancelJob(e);
    }
  }

  /// Retries failed job [id]. Returns copy for a refusal, or null when it
  /// worked.
  Future<String?> retry(int id) async {
    try {
      await _retryJob(id);
    } catch (e) {
      return Errors.retryJob(e);
    }
    await load();
    return null;
  }

  /// The announcement for [job] finishing, or null when it has not completed
  /// or failed.
  static JobAnnouncement? announcementFor(Job job) {
    final relPath = job.params['relPath'];
    final format = job.params['format'];
    final isConversion =
        job.kind == JobKinds.videoTranscode &&
        relPath is String &&
        relPath.isNotEmpty &&
        format is String &&
        format.isNotEmpty;
    final conversion = isConversion
        ? '${relPath.split('/').last} to ${format.toUpperCase()}'
        : null;

    switch (job.status) {
      case JobStatus.completed:
        if (conversion == null) return JobAnnouncement(job.name);
        final serial = job.params['serial'];
        return JobAnnouncement(
          'Converted $conversion',
          actionLabel: 'Show',
          // The output lands beside the source.
          route: AppRoutes.containingFolder(
            relPath! as String,
            serial: serial is String ? serial : '',
          ),
        );
      case JobStatus.failed:
        return JobAnnouncement(
          Errors.jobFailed(
            action: conversion == null ? null : 'convert $conversion',
            name: job.name,
          ),
          actionLabel: 'View',
          route: AppRoutes.jobs,
        );
      default:
        return null;
    }
  }

  void _onEvent(FileEvent event) {
    final data = event.data;
    if (!event.kind.startsWith('job_') || data is! Map<String, dynamic>) {
      return;
    }
    final job = Job.fromJson(data);
    if (JobKinds.all.contains(job.kind)) {
      _apply(job);
      notifyListeners();
    }
    final announcement = announcementFor(job);
    if (announcement != null) _announcements.add(announcement);
    if (job.status == JobStatus.completed ||
        job.status == JobStatus.failed ||
        job.status == JobStatus.canceled) {
      unawaited(load());
    }
  }

  /// Replaces the job with [job]'s id, or puts [job] first as the newest.
  void _apply(Job job) {
    final index = _jobs.indexWhere((j) => j.id == job.id);
    _jobs = index < 0
        ? [job, ..._jobs]
        : [..._jobs.take(index), job, ..._jobs.skip(index + 1)];
    _syncTicker();
  }

  /// Ticks once a second while anything runs, so elapsed time stays live.
  void _syncTicker() {
    if (runningCount == 0) {
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
    _announcements.close();
    super.dispose();
  }

  static ValueListenable<String?> _appSession() =>
      AppSettings.instance.sessionTokenNotifier;

  static Stream<FileEvent> _appEvents() {
    EventsService.instance.start();
    return EventsService.instance.events;
  }
}
