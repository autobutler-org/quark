import 'package:flutter/foundation.dart';

/// The [Job.kind] strings the app knows about.
abstract final class JobKinds {
  /// Converting a video to another format.
  static const String videoTranscode = 'video-transcode';

  /// Every kind above, for a listing that shows them all.
  static const List<String> all = [videoTranscode];
}

/// Where a [Job] is in its life.
enum JobStatus {
  pending,
  running,
  completed,
  failed,
  canceled,

  /// A status this build of the app does not know, from a newer Quark.
  unknown,
}

/// A long-running task on the Quark, as `GET /api/v0/jobs` and the `job_*`
/// events describe it.
///
/// The job's `error` field is a server diagnostic and deliberately not read:
/// what a user sees for a failed job comes from `Errors`.
@immutable
class Job {
  const Job({
    required this.id,
    required this.kind,
    required this.name,
    required this.status,
    required this.createdAt,
    this.lane = '',
    this.params = const {},
    this.progress = 0,
    this.attempts = 0,
    this.startedAt,
    this.finishedAt,
  });

  final int id;

  /// What sort of task this is; see [JobKinds]. A String rather than an enum,
  /// so a kind added on the Quark never breaks parsing here.
  final String kind;

  /// The concurrency lane within [kind] the job runs in. For
  /// [JobKinds.videoTranscode] it is `copy` for a quick stream copy, the only
  /// conversion a Quark runs now; older ones also ran `encode` re-encodes.
  /// Empty for a kind with one lane.
  final String lane;

  /// A short description of the task, written by the Quark in English:
  /// "Convert vacation.mkv to MOV". A view that wants its own translatable
  /// label builds one from [kind] and [params] and falls back to this.
  final String name;

  /// The kind-specific inputs the job was queued with, unmodifiable. For
  /// [JobKinds.videoTranscode] that is `relPath`, `serial`, `format`, and
  /// `quality`.
  /// Empty when the Quark sends none.
  final Map<String, Object?> params;

  final JobStatus status;

  /// From 0 to 1.
  final double progress;

  /// How many times the job has started running: 0 before its first run, one
  /// more each time it runs again after a retry.
  final int attempts;

  final DateTime createdAt;

  /// Null until the job starts running.
  final DateTime? startedAt;

  /// Null until the job completes, fails, or is canceled.
  final DateTime? finishedAt;

  /// How long the job has run: start to finish, or start to now while it is
  /// still going. Null before it starts.
  Duration? get elapsed {
    final started = startedAt;
    if (started == null) return null;
    return (finishedAt ?? DateTime.now()).difference(started);
  }

  factory Job.fromJson(Map<String, dynamic> json) => Job(
    id: (json['id'] as num?)?.toInt() ?? 0,
    kind: json['kind'] as String? ?? '',
    lane: json['lane'] as String? ?? '',
    name: json['name'] as String? ?? '',
    params: switch (json['params']) {
      final Map<String, dynamic> params => Map<String, Object?>.unmodifiable(
        params,
      ),
      _ => const {},
    },
    status: JobStatus.values.asNameMap()[json['status']] ?? JobStatus.unknown,
    progress: (json['progress'] as num?)?.toDouble() ?? 0,
    attempts: (json['attempts'] as num?)?.toInt() ?? 0,
    createdAt:
        _parseTime(json['createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    startedAt: _parseTime(json['startedAt']),
    finishedAt: _parseTime(json['finishedAt']),
  );
}

DateTime? _parseTime(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
