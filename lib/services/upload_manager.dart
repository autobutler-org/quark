import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:quark/models/upload_conflict.dart';
import 'package:quark/models/upload_session.dart';
import 'package:quark/services/file_browser_actions.dart';
import 'package:quark/services/resumable_upload_service.dart';
import 'package:quark/services/upload_chunk_source.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/task_pool.dart';
import 'package:quark/utils/upload_config.dart';
import 'package:quark/utils/upload_session_record.dart';
import 'package:quark/utils/upload_session_store.dart';
import 'package:quark/utils/upload_tree_utils.dart';
import 'package:quark/utils/upload_unload_guard.dart';

/// The result of a run of the queue, emitted once it drains.
class UploadBatchResult {
  const UploadBatchResult({
    required this.total,
    required this.completed,
    required this.failed,
    this.declined = 0,
    this.cancelled = false,
    this.stoppedEarly = false,
    this.firstError,
    this.note,
  });

  /// Files enqueued.
  final int total;

  /// Files actually attempted. Below [total] when the run was cancelled or
  /// gave up.
  final int completed;

  final int failed;

  /// Files the user chose not to send after the Quark reported the name taken.
  final int declined;

  /// The user asked for it to stop.
  final bool cancelled;

  /// It stopped itself after [kMaxConsecutiveUploadFailures] in a row.
  final bool stoppedEarly;

  /// The first failure's message, so the report can say what went wrong rather
  /// than only how much did.
  final String? firstError;

  /// Something the user should know once it is over — that a cap was hit, say.
  /// Reported at the end rather than as a prompt beforehand: it is information,
  /// not a decision, and nothing should stand between "upload" and uploading.
  final String? note;

  int get succeeded => completed - failed - declined;

  /// Enqueued but never attempted, because the run stopped first.
  int get skipped => total - completed;

  bool get hadFailures => failed > 0;

  /// True when the run did not get through everything it was given.
  bool get endedEarly => cancelled || stoppedEarly;
}

/// How long one attempt at one file may take before it is treated as failed.
///
/// Nothing here can abort the request itself, so this frees the worker rather
/// than the connection. Without it a server that accepts a request and then
/// stops responding — an overloaded Raspberry Pi will — holds a worker
/// forever, and with every worker held the batch never ends and the UI never
/// unlocks. Generous, because a large file over a slow link is not a fault.
const Duration kUploadAttemptTimeout = Duration(minutes: 2);

/// How many times one file is attempted before it counts as failed.
///
/// A small server under load fails intermittently rather than permanently, and
/// the second attempt usually lands.
const int kMaxUploadAttempts = 3;

/// How many files may fail in a row before the batch gives up.
///
/// Past a handful the server is not having a bad moment, it is unwell, and
/// grinding through another two thousand files to prove it wastes the user's
/// time and buries the error.
const int kMaxConsecutiveUploadFailures = 5;

/// How many uploads are in flight at once.
///
/// A browser allows about six connections per host on HTTP/1.1, and the file
/// listing and device calls need some of those too — saturating the pool is
/// what made uploads look stalled in the first place. Four keeps the pipe busy
/// while leaving the rest of the app able to talk to the server.
const int kDefaultUploadConcurrency = 4;

/// Sends one file. Swapped out in tests; in the app it is the real upload.
typedef UploadSender =
    Future<void> Function({
      required String currentPath,
      required List<http.MultipartFile> selectedFiles,
      String? serial,
      UploadConflictChoice? conflict,
    });

/// Asks the user what to do about [fileName], whose name the Quark says is
/// taken. The answer decides whether the file is sent again, and how.
///
/// A run with no resolver — nothing on screen to ask with — counts the file as
/// failed rather than guessing, which is what keeps an upload from quietly
/// replacing someone's work.
typedef UploadConflictResolver =
    Future<UploadConflictAnswer> Function(
      String fileName, {
      required bool offerApplyToAll,
    });

/// Runs uploads independently of whatever is on screen.
///
/// Uploads used to live in the file browser's State, which tied them to the
/// page: navigating to another folder took the progress with it, and every
/// completed file published a server event that the page turned into a full
/// refresh — devices call plus listing call — so a folder upload fired two
/// extra requests per file, all competing with the uploads themselves for the
/// browser's handful of connections per host. The upload appeared to stall.
///
/// Owning the queue here is what makes an upload survive navigation and a
/// refresh: nothing in the widget tree can start, stop, or outlive it. A page
/// reload still ends an upload, because the bytes are read and sent by this
/// page — see [setUploadUnloadGuard], which is the one case that warns.
class UploadManager extends ChangeNotifier {
  UploadManager._()
    : _concurrency = kDefaultUploadConcurrency,
      _attemptTimeout = kUploadAttemptTimeout,
      _maxAttempts = kMaxUploadAttempts,
      _maxConsecutiveFailures = kMaxConsecutiveUploadFailures,
      _chunkSizeBytes = UploadConfig.chunkSizeBytes,
      _chunkedThresholdBytes = UploadConfig.chunkedUploadThresholdBytes,
      _maxChunkAttempts = UploadConfig.maxChunkAttempts,
      _chunkRetryBackoff = UploadConfig.chunkRetryBackoff;

  static final UploadManager instance = UploadManager._();

  /// For tests: an isolated manager, so one test's queue is not another's.
  @visibleForTesting
  UploadManager.forTesting({
    UploadSender? sender,
    ResumableUploadClient? sessionClient,
    UploadSessionStore? sessionStore,
    int concurrency = kDefaultUploadConcurrency,
    Duration attemptTimeout = kUploadAttemptTimeout,
    int maxAttempts = kMaxUploadAttempts,
    int maxConsecutiveFailures = kMaxConsecutiveUploadFailures,
    int chunkSizeBytes = UploadConfig.chunkSizeBytes,
    int chunkedThresholdBytes = UploadConfig.chunkedUploadThresholdBytes,
    int maxChunkAttempts = UploadConfig.maxChunkAttempts,
    Duration chunkRetryBackoff = UploadConfig.chunkRetryBackoff,
  }) : _sender = sender,
       _sessionClient = sessionClient,
       _sessionStore = sessionStore,
       _concurrency = concurrency,
       _attemptTimeout = attemptTimeout,
       _maxAttempts = maxAttempts,
       _maxConsecutiveFailures = maxConsecutiveFailures,
       _chunkSizeBytes = chunkSizeBytes,
       _chunkedThresholdBytes = chunkedThresholdBytes,
       _maxChunkAttempts = maxChunkAttempts,
       _chunkRetryBackoff = chunkRetryBackoff;

  UploadSender? _sender;
  ResumableUploadClient? _sessionClient;
  UploadSessionStore? _sessionStore;

  late final TaskPool<_QueuedUpload> _pool = TaskPool<_QueuedUpload>(
    concurrency: _concurrency,
    worker: _upload,
  );
  final int _concurrency;
  final Duration _attemptTimeout;
  final int _maxAttempts;
  final int _maxConsecutiveFailures;
  final int _chunkSizeBytes;
  final int _chunkedThresholdBytes;
  final int _maxChunkAttempts;
  final Duration _chunkRetryBackoff;

  ResumableUploadClient get _client =>
      _sessionClient ?? ResumableUploadService.instance;

  UploadSessionStore get _store => _sessionStore ?? uploadSessionStore;

  final StreamController<UploadBatchResult> _results =
      StreamController<UploadBatchResult>.broadcast();

  bool _running = false;
  int _total = 0;
  int _completed = 0;
  int _failed = 0;
  int _consecutiveFailures = 0;
  bool _cancelled = false;
  bool _stoppedEarly = false;
  String? _firstError;
  String? _note;
  int _declined = 0;

  /// Asked what to do when the Quark says a name is taken. Set by whatever is
  /// on screen while an upload runs, and cleared when it goes away.
  UploadConflictResolver? conflictResolver;

  /// The choice that stands for the rest of this run, once the user has ticked
  /// the box that says so.
  UploadConflictChoice? _runChoice;
  bool _runChoiceStands = false;

  /// One clash is asked about at a time. Four workers can hit a taken name at
  /// once, and four dialogs stacked on top of each other is not a question.
  Future<void> _prompts = Future<void>.value();

  final Map<String, ChunkedUploadProgress> _chunked = {};

  /// Emits once each time the queue drains.
  Stream<UploadBatchResult> get results => _results.stream;

  bool get isUploading => _running;

  /// Files in the current run, including any queued while it was already going.
  int get total => _total;

  int get completed => _completed;

  /// Byte progress for the files currently going up in chunks, keyed by their
  /// destination.
  ///
  /// [completed] counts whole files, which says nothing useful while a single
  /// four-gigabyte file is in flight — it sits at zero for as long as the
  /// upload takes. This is the finer reading, published on the same
  /// [ChangeNotifier] and updated once per committed chunk, so a listener that
  /// wants it pays a map write per 8 MiB and one that does not pays nothing.
  /// Small files never appear here; they are one request and have no interior.
  Map<String, ChunkedUploadProgress> get chunkedProgress =>
      Map.unmodifiable(_chunked);

  /// Drops everything not yet started and lets the run finish.
  ///
  /// Files already in flight are not interrupted — nothing here can abort an
  /// in-flight request — so the run ends once they return or time out, which
  /// [kUploadAttemptTimeout] bounds.
  void cancel() {
    if (!_running) {
      return;
    }
    _cancelled = true;
    _pool.clear();
    notifyListeners();
  }

  /// Adds [uploads] to the queue and starts draining if nothing is running.
  ///
  /// Returns immediately: the caller is a button handler, not the owner of the
  /// work. Enqueuing during a run extends it rather than starting a second one,
  /// so uploads never compete with each other for connections.
  void enqueue({
    required List<PendingUpload> uploads,
    required String uploadPath,
    String? serial,
    String? note,
  }) {
    if (uploads.isEmpty) {
      return;
    }
    if (note != null && note.isNotEmpty) {
      _note = note;
    }

    // Grouped so every file bound for one directory is sent together, and the
    // target path is resolved once per directory rather than once per file.
    for (final group in groupByRelativeDir(uploads).entries) {
      final targetPath = uploadTargetPath(uploadPath, group.key);
      for (final upload in group.value) {
        _pool.add(_QueuedUpload(upload, targetPath, serial));
      }
    }

    _total += uploads.length;
    notifyListeners();

    if (!_running) {
      unawaited(_drain());
    }
  }

  Future<void> _drain() async {
    _running = true;
    setUploadUnloadGuard(active: true);
    notifyListeners();

    try {
      // TaskPool handles the fan-out and picks up anything enqueued mid-run.
      // Failures are counted in _upload rather than thrown, so this does not
      // need to guard against one file taking the batch down.
      await _pool.drain();
    } finally {
      final result = UploadBatchResult(
        total: _total,
        completed: _completed,
        failed: _failed,
        declined: _declined,
        cancelled: _cancelled,
        stoppedEarly: _stoppedEarly,
        firstError: _firstError,
        note: _note,
      );
      _running = false;
      _total = 0;
      _completed = 0;
      _failed = 0;
      _declined = 0;
      _runChoice = null;
      _runChoiceStands = false;
      _consecutiveFailures = 0;
      _cancelled = false;
      _stoppedEarly = false;
      _firstError = null;
      _note = null;
      _chunked.clear();
      setUploadUnloadGuard(active: false);
      notifyListeners();
      if (!_results.isClosed) {
        _results.add(result);
      }
    }
  }

  /// Sends one file by whichever route its size calls for.
  ///
  /// Opening the chunk source is how the size becomes known, so it happens
  /// first and costs a handle rather than a read. A file the platform cannot
  /// open a range at a time — or one small enough not to need it — falls
  /// through to the single multipart POST that has always carried uploads
  /// (#1629).
  Future<void> _upload(_QueuedUpload queued) async {
    try {
      await _attempt(queued);
    } on _NameTaken {
      // The Quark refuses a name it already has rather than renaming the file
      // behind the user's back (#2016), so the user decides and the file goes
      // again saying what they chose.
      final answer = await _answerForConflict(queued.upload.name);
      if (answer == null) {
        _recordFailure(queued.upload.name, Errors.fileNameTaken);
        return;
      }
      final choice = answer.choice;
      if (choice == null) {
        _recordDeclined();
        return;
      }
      try {
        await _attempt(queued.withConflict(choice));
      } on _NameTaken {
        // Keeping both picks a free name and replacing takes the name it
        // asked for, so a second clash is the Quark disagreeing with itself.
        _recordFailure(queued.upload.name, Errors.fileNameTaken);
      }
    }
  }

  /// The user's answer for [fileName], or null when there is nobody to ask.
  ///
  /// Serialized, so a batch that hits four clashes at once asks four times in
  /// turn rather than all at once — and, once the user says the answer stands
  /// for the rest of the upload, stops asking at all.
  Future<UploadConflictAnswer?> _answerForConflict(String fileName) {
    final asked = _prompts.then((_) async {
      if (_runChoiceStands) {
        return UploadConflictAnswer(choice: _runChoice);
      }
      final resolver = conflictResolver;
      if (resolver == null) {
        return null;
      }
      if (_cancelled || _stoppedEarly) {
        return const UploadConflictAnswer(choice: null);
      }
      final answer = await resolver(fileName, offerApplyToAll: _total > 1);
      if (answer.applyToAll) {
        _runChoiceStands = true;
        _runChoice = answer.choice;
      }
      return answer;
    });
    // The queue must keep moving whatever one prompt did.
    _prompts = asked.then((_) {}, onError: (_) {});
    return asked;
  }

  /// Counts a file the user chose not to send. Not a failure: nothing went
  /// wrong, and it must not count toward the run giving up.
  void _recordDeclined() {
    _declined++;
    _completed++;
    notifyListeners();
  }

  /// Sends one file, by whichever route its size calls for.
  Future<void> _attempt(_QueuedUpload queued) async {
    final source = await _openChunkSource(queued.upload);
    if (source == null) {
      return _uploadWhole(queued);
    }

    try {
      if (source.size < _chunkedThresholdBytes) {
        return await _uploadWhole(queued);
      }
      return await _uploadChunked(queued, source);
    } finally {
      source.release();
    }
  }

  Future<UploadChunkSource?> _openChunkSource(PendingUpload upload) async {
    final open = upload.openChunkSource;
    if (open == null) {
      return null;
    }
    try {
      return await open();
    } catch (e) {
      // Not a failure on its own: the whole-file path may still manage it, and
      // if it cannot, that is where the file is counted as failed.
      debugPrint(
        '[upload_manager.dart] ${upload.name} could not be opened for '
        'chunking: $e',
      );
      return null;
    }
  }

  /// Sends one file, retrying a few times. A failure is counted, never
  /// rethrown — one unreadable file must not take the rest of the folder with
  /// it.
  Future<void> _uploadWhole(_QueuedUpload queued) async {
    Object? lastError;

    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        // Rebuilt every attempt: a multipart file's body is a stream that can
        // only be read once, so a retry needs a fresh one. Built here, as it
        // is sent, so only [_concurrency] files are ever live at a time.
        final file = await queued.upload.build();
        if (file == null) {
          _recordFailure(
            queued.upload.name,
            Errors.couldNot('read ${queued.upload.name}'),
          );
          return;
        }
        await _send(
          currentPath: queued.targetPath,
          selectedFiles: [file],
          serial: queued.serial,
          conflict: queued.conflict,
        ).timeout(
          _attemptTimeout,
          onTimeout: () =>
              throw TimeoutException('no response after $_attemptTimeout'),
        );

        _consecutiveFailures = 0;
        _completed++;
        notifyListeners();
        return;
      } catch (e) {
        if (_isNameTaken(e)) {
          // Retrying cannot free the name, and the backoff would only delay
          // the question.
          throw const _NameTaken();
        }
        lastError = e;
        debugPrint(
          '[upload_manager.dart] ${queued.upload.name} attempt $attempt/'
          '$_maxAttempts failed: $e',
        );
        if (attempt < _maxAttempts && !_cancelled && !_stoppedEarly) {
          // Backing off rather than retrying straight away: an overloaded
          // server needs a moment, and hammering it is what caused this.
          await Future<void>.delayed(Duration(seconds: attempt));
        } else {
          break;
        }
      }
    }

    _recordFailure(
      queued.upload.name,
      Errors.message(lastError, 'upload ${queued.upload.name}'),
    );
  }

  /// Sends one large file through a resumable session, a chunk at a time.
  ///
  /// The concurrency above this is untouched — this changes what one worker
  /// does, not how many run, and nothing here sends two chunks of the same
  /// file at once.
  Future<void> _uploadChunked(
    _QueuedUpload queued,
    UploadChunkSource source,
  ) async {
    final total = source.size;
    final name = queued.upload.name;
    final rootDir = toRootDir(queued.targetPath);
    final progressKey = '${queued.targetPath}/$name';
    final fileKey = uploadFileIdentity(
      rootDir: rootDir,
      fileName: name,
      size: total,
      lastModified: source.lastModified,
    );

    Object? lastError;

    // The outer loop exists for one case: a session the server no longer knows
    // about. Sessions live in its memory, so a restart drops them, and nothing
    // can resume what is not there — the file has to start again behind a new
    // session. Bounded, or a server that keeps losing them would loop here
    // forever.
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final finished = await _runUploadSession(
          queued: queued,
          source: source,
          total: total,
          rootDir: rootDir,
          fileKey: fileKey,
          progressKey: progressKey,
        );
        if (finished) {
          _store.remove(fileKey);
          _chunked.remove(progressKey);
          _consecutiveFailures = 0;
          _completed++;
          notifyListeners();
          return;
        }
        _store.remove(fileKey);
        lastError = const MessageException(
          'The upload session expired before it finished.',
        );
      } on _UploadStopped {
        // Neither sent nor failed: the run is ending and this file stopped on
        // a chunk boundary. The session ends with it, so its staged bytes go
        // now rather than sitting on the server's disk until they expire.
        _abandonStoredSession(fileKey);
        _chunked.remove(progressKey);
        return;
      } catch (e) {
        if (_isNameTaken(e)) {
          _abandonStoredSession(fileKey);
          _chunked.remove(progressKey);
          throw const _NameTaken();
        }
        lastError = e;
        debugPrint(
          '[upload_manager.dart] $name session attempt $attempt/$_maxAttempts '
          'failed: $e',
        );
      }

      if (attempt >= _maxAttempts || _cancelled || _stoppedEarly) {
        break;
      }
      await Future<void>.delayed(Duration(seconds: attempt));
    }

    _abandonStoredSession(fileKey);
    _chunked.remove(progressKey);
    _recordFailure(name, Errors.message(lastError, 'upload $name'));
  }

  /// Forgets the session stored for [fileKey] and tells the server to drop it.
  ///
  /// Every way a file stops using its session other than a commit comes
  /// through here: the server discards a session only when it commits, so one
  /// the client walks away from keeps its staged bytes until it expires.
  void _abandonStoredSession(String fileKey) {
    final record = _store.read(fileKey);
    _store.remove(fileKey);
    if (record != null) {
      _abandonSession(record.sessionId);
    }
  }

  /// Best effort and never awaited: tidying up must not hold a worker or turn
  /// an outcome into a different one.
  void _abandonSession(String sessionId) {
    unawaited(
      _client
          .deleteSession(sessionId)
          .then<void>(
            (_) {},
            onError: (Object e) => debugPrint(
              '[upload_manager.dart] Could not drop session $sessionId: $e',
            ),
          ),
    );
  }

  /// Runs one session to the end of the file.
  ///
  /// Returns true when the server said the file was committed, false when the
  /// session disappeared mid-file and the caller should open another. Anything
  /// else throws. Holding every byte is not the same as committed: see the
  /// replay below.
  Future<bool> _runUploadSession({
    required _QueuedUpload queued,
    required UploadChunkSource source,
    required int total,
    required String rootDir,
    required String fileKey,
    required String progressKey,
  }) async {
    final name = queued.upload.name;

    final resumed = await _resumeSession(
      fileKey: fileKey,
      total: total,
      fileName: name,
    );
    var record =
        resumed ??
        await _openSession(
          queued: queued,
          rootDir: rootDir,
          total: total,
          fileKey: fileKey,
        );

    var offset = record.offset;
    _store.write(record);
    _reportChunkProgress(progressKey, name, offset, total);

    // A resync that does not move is a server disagreeing with itself. Counted
    // rather than trusted, so a stuck offset ends the file instead of spinning
    // on it.
    var stalledResyncs = 0;

    while (true) {
      // A chunk boundary is a real stopping point, which a whole-file upload
      // never had: the session and its offset survive, so stopping here costs
      // at most one chunk rather than the whole file. Without this a cancel
      // during a four-gigabyte upload would do nothing for the twenty minutes
      // it takes to finish, and the UI would stay locked throughout.
      if (_cancelled || _stoppedEarly) {
        throw const _UploadStopped();
      }

      // A session with every byte staged but still open is one whose commit
      // failed — a full disk, say. The server commits again when the final
      // chunk is replayed, so resend it rather than calling the file done.
      final start = offset < total
          ? offset
          : math.max(0, total - _chunkSizeBytes);
      final end = math.min(start + _chunkSizeBytes, total);
      final outcome = await _sendChunk(
        sessionId: record.sessionId,
        source: source,
        start: start,
        end: end,
        total: total,
      );

      switch (outcome) {
        case ChunkAccepted(offset: final committed, complete: final complete):
          offset = committed;
          record = record.copyWith(offset: offset);
          _store.write(record);
          _reportChunkProgress(progressKey, name, offset, total);
          if (complete) {
            return true;
          }
          if (offset >= total) {
            throw Exception('server holds all of $name but did not commit it');
          }
        case ChunkOffsetMismatch(offset: final committed):
          // Almost always a chunk whose response was lost on the way back: the
          // server has the bytes, we do not know it. Resyncing costs one
          // header; restarting the file would cost everything sent so far.
          if (committed <= offset) {
            stalledResyncs++;
            if (stalledResyncs > _maxChunkAttempts) {
              throw Exception(
                'server kept reporting offset $committed for $name',
              );
            }
          } else {
            stalledResyncs = 0;
          }
          offset = committed;
          record = record.copyWith(offset: offset);
          _store.write(record);
          _reportChunkProgress(progressKey, name, offset, total);
        case ChunkSessionGone():
          return false;
        case ChunkRejected():
          throw Exception('$outcome');
      }
    }
  }

  Future<UploadSessionRecord> _openSession({
    required _QueuedUpload queued,
    required String rootDir,
    required int total,
    required String fileKey,
  }) async {
    final session = await _client.createSession(
      rootDir: rootDir,
      fileName: queued.upload.name,
      totalSize: total,
      serial: queued.serial,
      conflict: queued.conflict,
    );
    return UploadSessionRecord(
      fileKey: fileKey,
      sessionId: session.sessionId,
      offset: session.offset,
      totalSize: total,
      fileName: queued.upload.name,
      createdAt: DateTime.now(),
    );
  }

  /// The session a stored record points at, once the server has agreed it is
  /// the same file.
  ///
  /// Null means start fresh. The record's own offset is never trusted over the
  /// server's: it is a hint that a session may exist, and everything else
  /// comes from the answer.
  Future<UploadSessionRecord?> _resumeSession({
    required String fileKey,
    required int total,
    required String fileName,
  }) async {
    final store = _store;
    store.pruneStale();

    final record = store.read(fileKey);
    if (record == null) {
      return null;
    }

    try {
      final status = await _client.getSession(record.sessionId);
      // A session that is gone, or that describes a different file, is not a
      // resume. Appending to it would corrupt whatever it is holding, and the
      // identity that got us here is deliberately weak — see
      // [uploadFileIdentity].
      if (status == null ||
          status.totalSize != total ||
          status.fileName != fileName) {
        store.remove(fileKey);
        if (status != null) {
          // We are the only thing that knew about this session and we have
          // just decided not to use it. Saying so frees its temp file now
          // rather than leaving it for the server's sweeper.
          _abandonSession(record.sessionId);
        }
        return null;
      }
      return record.copyWith(offset: status.offset);
    } catch (e) {
      debugPrint(
        '[upload_manager.dart] Could not check session ${record.sessionId}, '
        'starting $fileName over: $e',
      );
      // It may well still exist; a new one is about to replace it.
      store.remove(fileKey);
      _abandonSession(record.sessionId);
      return null;
    }
  }

  /// Sends one chunk, retrying the same range on a transport failure.
  ///
  /// A retry resends the range the server is waiting for, never the file — the
  /// committed offset is the whole point of the protocol.
  Future<ChunkUploadOutcome> _sendChunk({
    required String sessionId,
    required UploadChunkSource source,
    required int start,
    required int end,
    required int total,
  }) async {
    Object? lastError;

    for (var attempt = 1; attempt <= _maxChunkAttempts; attempt++) {
      try {
        // [kUploadAttemptTimeout] bounds one chunk here rather than one file.
        // It has to: a multi-gigabyte upload is minutes of honest work, and a
        // timeout that covered the whole of it would fail every large file on
        // principle. A chunk is a fixed size, so a chunk that has said nothing
        // for two minutes really is stuck.
        return await _client
            .putChunk(
              sessionId: sessionId,
              source: source,
              start: start,
              end: end,
              totalSize: total,
            )
            .timeout(
              _attemptTimeout,
              onTimeout: () =>
                  throw TimeoutException('no response after $_attemptTimeout'),
            );
      } catch (e) {
        lastError = e;
        debugPrint(
          '[upload_manager.dart] chunk $start-$end attempt $attempt/'
          '$_maxChunkAttempts failed: $e',
        );
        if (attempt >= _maxChunkAttempts || _cancelled || _stoppedEarly) {
          break;
        }
        await Future<void>.delayed(_chunkRetryBackoff * attempt);
      }
    }

    throw lastError ?? Exception('chunk $start-$end could not be sent');
  }

  void _reportChunkProgress(String key, String name, int sent, int total) {
    _chunked[key] = ChunkedUploadProgress(name: name, sent: sent, total: total);
    notifyListeners();
  }

  void _recordFailure(String name, String reason) {
    _failed++;
    _completed++;
    _firstError ??= reason;
    _consecutiveFailures++;

    if (_consecutiveFailures >= _maxConsecutiveFailures && !_stoppedEarly) {
      _stoppedEarly = true;
      final dropped = _pool.clear();
      debugPrint(
        '[upload_manager.dart] $_consecutiveFailures uploads failed in a row '
        '($name last); abandoning $dropped still queued',
      );
    }

    notifyListeners();
  }

  Future<void> _send({
    required String currentPath,
    required List<http.MultipartFile> selectedFiles,
    String? serial,
    UploadConflictChoice? conflict,
  }) {
    final sender = _sender ?? uploadMultipartFilesToCurrentPath;
    return sender(
      currentPath: currentPath,
      selectedFiles: selectedFiles,
      serial: serial,
      conflict: conflict,
    );
  }

  @override
  void dispose() {
    _results.close();
    super.dispose();
  }
}

/// Leaves a chunked file where it stands because the run is ending.
///
/// Not a failure: nothing went wrong, and the file is picked up from the
/// server's offset next time rather than counted against the batch.
class _UploadStopped implements Exception {
  const _UploadStopped();
}

/// How far one chunked file has got, in bytes.
class ChunkedUploadProgress {
  const ChunkedUploadProgress({
    required this.name,
    required this.sent,
    required this.total,
  });

  final String name;

  /// Bytes the server has committed. Never a local tally — see
  /// [ChunkAccepted.offset].
  final int sent;

  final int total;

  double get fraction => total <= 0 ? 0 : sent / total;
}

class _QueuedUpload {
  const _QueuedUpload(
    this.upload,
    this.targetPath,
    this.serial, [
    this.conflict,
  ]);

  final PendingUpload upload;
  final String targetPath;
  final String? serial;

  /// What the user said to do about a name the Quark already has, once they
  /// have been asked. Null on the first attempt.
  final UploadConflictChoice? conflict;

  _QueuedUpload withConflict(UploadConflictChoice choice) =>
      _QueuedUpload(upload, targetPath, serial, choice);
}

/// The Quark refused a file because its name is taken and nothing said what to
/// do about it. Carried out to [UploadManager._upload], which asks.
class _NameTaken implements Exception {
  const _NameTaken();
}

/// Whether [error] is the Quark saying a name is taken.
bool _isNameTaken(Object error) =>
    error is ApiException && error.statusCode == 409;
