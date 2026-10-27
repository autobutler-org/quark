import 'package:quark/models/music_track.dart';

/// A track the signed-in user has played, from `GET /api/v0/music/history`:
/// the track, how often they played it, and when last.
class MusicPlay {
  /// Creates a played track.
  const MusicPlay({required this.track, this.playCount = 0, this.lastPlayedAt});

  /// The track played.
  final MusicTrack track;

  /// How many plays the Quark has counted for this user.
  final int playCount;

  /// When the last play was counted, or null when the Quark sent none.
  final DateTime? lastPlayedAt;

  /// Reads one played track from the API's JSON.
  factory MusicPlay.fromJson(Map<String, dynamic> json) => MusicPlay(
    track: MusicTrack.fromJson(
      json['track'] as Map<String, dynamic>? ?? const {},
    ),
    playCount: (json['playCount'] as num?)?.toInt() ?? 0,
    lastPlayedAt: switch (json['lastPlayedAt']) {
      final String at => DateTime.tryParse(at),
      _ => null,
    },
  );
}
