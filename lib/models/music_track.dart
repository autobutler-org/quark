/// One song in the Quark's music library, as `GET /api/v0/music/tracks`
/// lists it: where its file is, and the tags the Music page shows.
class MusicTrack {
  const MusicTrack({
    required this.relPath,
    this.serial = '',
    this.title = '',
    this.artist = '',
    this.albumArtist = '',
    this.album = '',
    this.albumKey = '',
    this.genre = '',
    this.durationMs = 0,
    this.hasCover = false,
  });

  /// Reads one entry of `GET /api/v0/music/tracks`' `tracks`.
  factory MusicTrack.fromJson(Map<String, dynamic> json) => MusicTrack(
    relPath: json['relPath']?.toString() ?? '',
    serial: json['serial']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    artist: json['artist']?.toString() ?? '',
    albumArtist: json['albumArtist']?.toString() ?? '',
    album: json['album']?.toString() ?? '',
    albumKey: json['albumKey']?.toString() ?? '',
    genre: json['genre']?.toString() ?? '',
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    hasCover: json['hasCover'] == true,
  );

  /// The file's path within its device's files.
  final String relPath;

  /// The device holding the file, empty for the internal drive.
  final String serial;

  /// The tagged title, or the file name without its extension.
  final String title;

  /// The track artist, empty when untagged.
  final String artist;

  /// The album artist, the track artist when untagged.
  final String albumArtist;

  /// The album title, empty when untagged.
  final String album;

  /// The album's identity, which `GET /api/v0/music/tracks` filters on.
  final String albumKey;

  /// The genre, empty when untagged.
  final String genre;

  /// The playing time in milliseconds, 0 when unknown.
  final int durationMs;

  /// Whether the file has embedded or folder cover art.
  final bool hasCover;
}
