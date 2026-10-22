import 'package:flutter/foundation.dart';

import 'package:quark/models/job.dart';
import 'package:quark/utils/playback_time.dart';

/// The clip a trim job saved: where it landed and where it is shown from.
/// That is the requested start, except for a start before the video's first
/// keyframe or past its last frame, or a TS output, where the clip begins on
/// a keyframe instead.
@immutable
class TrimResult {
  const TrimResult({required this.relPath, required this.actualStart});

  /// The relative path of the saved clip.
  final String relPath;

  /// Where the clip begins in the source video.
  final Duration actualStart;

  factory TrimResult.fromJson(Map<String, dynamic> json) => TrimResult(
    relPath: json['relPath'] as String,
    actualStart: Duration(
      milliseconds: (json['actualStartMs'] as num? ?? 0).toInt(),
    ),
  );

  /// The result a completed [JobKinds.videoTrim] job saved in its detail, or
  /// null for any other job, or one that saved none.
  static TrimResult? fromJob(Job job) {
    final relPath = job.detail['relPath'];
    if (job.kind != JobKinds.videoTrim ||
        job.status != JobStatus.completed ||
        relPath is! String ||
        relPath.isEmpty) {
      return null;
    }
    return TrimResult.fromJson(Map<String, dynamic>.from(job.detail));
  }

  /// The start [job] was queued with, which [savedMessage] compares against.
  static Duration requestedStart(Job job) => Duration(
    milliseconds: switch (job.params['startMs']) {
      final num ms => ms.toInt(),
      _ => 0,
    },
  );

  /// The confirmation shown once the clip is saved. When the clip starts at
  /// a different displayed time than [requestedStart], it also says where.
  String savedMessage(Duration requestedStart) {
    final saved = 'Clip saved as ${relPath.split('/').last}.';
    final actual = formatPlaybackTime(actualStart);
    final requested = formatPlaybackTime(requestedStart);
    if (actual == requested) return saved;
    return '$saved It starts at $actual instead of $requested, the closest '
        'point this video can be cut.';
  }
}
