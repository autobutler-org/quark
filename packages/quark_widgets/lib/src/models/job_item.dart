import 'package:flutter/foundation.dart';

/// Where a [JobItem] is in its life.
enum JobItemStatus {
  /// Queued and waiting for a slot.
  pending,

  /// Running now; [JobItem.progress] is meaningful.
  running,

  /// Finished successfully.
  completed,

  /// Stopped with an error. A caller may offer a retry.
  failed,

  /// Stopped by a user.
  canceled,

  /// A status the caller could not name.
  unknown,
}

/// One long-running task as a `JobList` renders it.
///
/// Everything here is already decided: whether the job can be canceled or
/// retried, how long it has run, whether it is a quick copy. The list only
/// draws it.
@immutable
class JobItem {
  /// Creates a job item.
  const JobItem({
    required this.id,
    required this.name,
    required this.status,
    this.progress = 0,
    this.attempts = 0,
    this.elapsed,
    this.isQuickCopy = false,
    this.canCancel = false,
    this.canRetry = false,
  });

  /// The job's stable identifier, and what the list's callbacks carry.
  final int id;

  /// What the job does, for example "Convert vacation.mkv to MOV".
  final String name;

  /// Where the job is in its life.
  final JobItemStatus status;

  /// From 0 to 1, drawn as a bar while [status] is running.
  final double progress;

  /// How many times the job has started running.
  final int attempts;

  /// How long the job has run. Null before it starts.
  final Duration? elapsed;

  /// Whether the job is a quick stream copy rather than a full re-encode.
  final bool isQuickCopy;

  /// Whether a Cancel action is offered.
  final bool canCancel;

  /// Whether a Retry action is offered.
  final bool canRetry;
}
