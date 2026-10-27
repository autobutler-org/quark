/// An album in the music library, as `GET /api/v0/music/albums` returns it:
/// the tracks sharing one [albumKey] that the signed-in user can read.
class MusicAlbum {
  /// Creates an album.
  const MusicAlbum({
    required this.albumKey,
    required this.title,
    this.albumArtist = '',
    this.year = 0,
    this.trackCount = 0,
    this.durationMs = 0,
    this.coverSerial = '',
    this.coverPath = '',
  });

  /// The album's identity: album artist, title, device and folder.
  final String albumKey;

  /// The album title, '' when its tracks are untagged.
  final String title;

  /// The album artist.
  final String albumArtist;

  /// The earliest tagged year among the tracks, 0 when none is.
  final int year;

  /// How many of its tracks the user can read.
  final int trackCount;

  /// The total playing time in milliseconds.
  final int durationMs;

  /// The device of the track to ask the thumbnail endpoint for.
  final String coverSerial;

  /// The track to ask the thumbnail endpoint for: one with cover art when
  /// any has it, '' when the album has no tracks to show.
  final String coverPath;

  /// Reads one album from the API's JSON.
  factory MusicAlbum.fromJson(Map<String, dynamic> json) => MusicAlbum(
    albumKey: json['albumKey'] as String? ?? '',
    title: json['title'] as String? ?? '',
    albumArtist: json['albumArtist'] as String? ?? '',
    year: (json['year'] as num?)?.toInt() ?? 0,
    trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    coverSerial: json['coverSerial'] as String? ?? '',
    coverPath: json['coverPath'] as String? ?? '',
  );
}
