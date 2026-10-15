import 'package:flutter/foundation.dart';

import 'music_track_item.dart';

/// One music search hit: its track and the caller-provided matching excerpt.
@immutable
class MusicSearchResult {
  /// Creates a search hit for [track].
  const MusicSearchResult({required this.track, required this.snippet});

  /// The track that matched.
  final MusicTrackItem track;

  /// The API's human-readable excerpt showing why [track] matched.
  final String snippet;
}
