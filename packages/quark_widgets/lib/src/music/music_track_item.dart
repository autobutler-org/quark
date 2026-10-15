import 'package:flutter/foundation.dart';

/// The immutable song metadata rendered by music widgets.
@immutable
class MusicTrackItem {
  /// Creates one track from the fields returned by the music API.
  const MusicTrackItem({
    required this.path,
    required this.title,
    this.serial = '',
    this.artist = '',
    this.album = '',
    this.duration,
  });

  /// The path relative to the track's device, used as its stable widget id.
  final String path;

  /// The device serial, or an empty string for the internal drive.
  final String serial;

  /// The display title, already falling back to the file name when untagged.
  final String title;

  /// The track artist, or an empty string when the file has no artist tag.
  final String artist;

  /// The album title, or an empty string when the file has no album tag.
  final String album;

  /// The playback duration, or null when it could not be read.
  final Duration? duration;
}
