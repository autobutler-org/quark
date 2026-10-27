/// One song in the music library, as `GET /api/v0/music/tracks` returns it.
///
/// [serial] and [relPath] name the file: the device holding it ('' for the
/// internal drive) and its path in that device's files namespace. They are
/// what the file viewer, the download and the cover thumbnail are asked for.
class MusicTrack {
  /// Creates a track.
  const MusicTrack({
    required this.relPath,
    required this.title,
    this.serial = '',
    this.artist = '',
    this.albumArtist = '',
    this.album = '',
    this.albumKey = '',
    this.genre = '',
    this.trackNo = 0,
    this.discNo = 0,
    this.year = 0,
    this.durationMs = 0,
    this.durationExact = true,
    this.hasCover = false,
  });

  /// The device holding the file, '' for the internal drive.
  final String serial;

  /// The file's path within its device.
  final String relPath;

  /// The tagged title, or the file name without its extension.
  final String title;

  /// The track artist, '' when untagged.
  final String artist;

  /// The album artist, the track artist when untagged.
  final String albumArtist;

  /// The album title, '' when untagged.
  final String album;

  /// The album's identity for `/music/albums/<key>`.
  final String albumKey;

  /// The genre, '' when untagged.
  final String genre;

  /// The track number, 0 when untagged.
  final int trackNo;

  /// The disc number, 0 when untagged.
  final int discNo;

  /// The release year, 0 when untagged.
  final int year;

  /// The playing time in milliseconds, 0 when unknown.
  final int durationMs;

  /// False when [durationMs] is an estimate from the bitrate.
  final bool durationExact;

  /// Whether the file has embedded or folder cover art.
  final bool hasCover;

  /// The playing time, or null when it is unknown.
  Duration? get duration =>
      durationMs > 0 ? Duration(milliseconds: durationMs) : null;

  /// Reads one track from the API's JSON.
  factory MusicTrack.fromJson(Map<String, dynamic> json) => MusicTrack(
    serial: json['serial'] as String? ?? '',
    relPath: json['relPath'] as String? ?? '',
    title: json['title'] as String? ?? '',
    artist: json['artist'] as String? ?? '',
    albumArtist: json['albumArtist'] as String? ?? '',
    album: json['album'] as String? ?? '',
    albumKey: json['albumKey'] as String? ?? '',
    genre: json['genre'] as String? ?? '',
    trackNo: (json['trackNo'] as num?)?.toInt() ?? 0,
    discNo: (json['discNo'] as num?)?.toInt() ?? 0,
    year: (json['year'] as num?)?.toInt() ?? 0,
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    durationExact: json['durationExact'] as bool? ?? true,
    hasCover: json['hasCover'] as bool? ?? false,
  );
}

/// One music search hit: the track and the excerpt showing why it matched.
class MusicSearchHit {
  /// Creates a hit.
  const MusicSearchHit({required this.track, this.snippet = ''});

  /// The track that matched.
  final MusicTrack track;

  /// The matched text, as the Quark highlighted it.
  final String snippet;

  /// Reads one hit from `GET /api/v0/music/search`.
  factory MusicSearchHit.fromJson(Map<String, dynamic> json) => MusicSearchHit(
    track: MusicTrack.fromJson(
      json['track'] as Map<String, dynamic>? ?? const {},
    ),
    snippet: json['snippet'] as String? ?? '',
  );
}
