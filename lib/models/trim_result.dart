import 'package:flutter/foundation.dart';

import 'package:quark/utils/playback_time.dart';

/// The clip `POST /api/v0/videos/trim` saved: where it landed and where it
/// is shown from. That is the requested start, except for a start before the
/// video's first keyframe or past its last frame, or a TS output, where the
/// clip begins on a keyframe instead.
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
