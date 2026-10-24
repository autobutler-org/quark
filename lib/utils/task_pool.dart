import 'dart:async';
import 'dart:collection';

/// Runs queued work with a bounded number of tasks in flight.
///
/// A pool over one shared queue, not fixed batches: a batch of four runs at the
/// speed of its slowest member, leaving the other three idle until it finishes,
/// while a worker here takes the next item the moment it is free. That matters
/// whenever items vary in cost — a folder of files where one is much larger
/// than the rest, say.
///
/// Items added while draining join the run in progress rather than waiting for
/// the next one, and [drain] called during a run returns that run instead of
/// starting a second.
///
/// ```dart
/// final pool = TaskPool<Job>(concurrency: 4, worker: (job) => job.run());
/// jobs.forEach(pool.add);
/// await pool.drain();
/// ```
class TaskPool<T> {
  TaskPool({required this.concurrency, required this.worker})
    : assert(concurrency > 0, 'concurrency must be at least 1');

  /// How many items may be in flight at once.
  final int concurrency;

  /// Handles one item. Called at most [concurrency] times concurrently.
  ///
  /// A throw does not strand the rest: the pool keeps draining and rethrows the
  /// first error once it is done. Callers that want per-item failures counted
  /// rather than thrown should catch inside their own worker.
  final Future<void> Function(T item) worker;

  final Queue<T> _queue = Queue<T>();

  Future<void>? _run;
  Object? _firstError;
  StackTrace? _firstStackTrace;

  void add(T item) => _queue.add(item);

  /// Drops everything not yet started.
  ///
  /// Items already in flight are not interrupted — there is nothing to
  /// interrupt them with — so a [drain] in progress ends once they finish.
  /// Returns how many were dropped.
  int clear() {
    final dropped = _queue.length;
    _queue.clear();
    return dropped;
  }

  /// Works through the queue, [concurrency] at a time, until nothing is left.
  ///
  /// Rethrows the first error a worker threw, after everything else has run.
  Future<void> drain() {
    final running = _run;
    if (running != null) {
      return running;
    }

    _firstError = null;
    _firstStackTrace = null;

    final run = _drainAll().whenComplete(() {
      _run = null;
    });
    _run = run;
    return run;
  }

  Future<void> _drainAll() async {
    // The outer loop picks up anything added while the workers were busy.
    // Nothing can slip past it: no await separates the check from the exit.
    while (_queue.isNotEmpty) {
      await Future.wait([for (var i = 0; i < concurrency; i++) _worker()]);
    }

    final error = _firstError;
    if (error != null) {
      Error.throwWithStackTrace(error, _firstStackTrace ?? StackTrace.current);
    }
  }

  Future<void> _worker() async {
    // Single-threaded, so removeFirst between awaits cannot hand one item to
    // two workers.
    while (_queue.isNotEmpty) {
      final item = _queue.removeFirst();
      try {
        await worker(item);
      } catch (error, stackTrace) {
        _firstError ??= error;
        _firstStackTrace ??= stackTrace;
      }
    }
  }
}
