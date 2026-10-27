/// An album artist in the music library, as `GET /api/v0/music/artists`
/// returns it, counting only what the signed-in user can read.
class MusicArtist {
  /// Creates an artist.
  const MusicArtist({
    required this.name,
    this.albumCount = 0,
    this.trackCount = 0,
    this.coverSerial = '',
    this.coverPath = '',
  });

  /// The artist's name, '' for untagged tracks.
  final String name;

  /// How many albums are credited to the artist.
  final int albumCount;

  /// How many tracks are credited to the artist.
  final int trackCount;

  /// The device of the track whose cover stands for the artist.
  final String coverSerial;

  /// The track whose cover stands for the artist.
  final String coverPath;

  /// Reads one artist from the API's JSON.
  factory MusicArtist.fromJson(Map<String, dynamic> json) => MusicArtist(
    name: json['name'] as String? ?? '',
    albumCount: (json['albumCount'] as num?)?.toInt() ?? 0,
    trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
    coverSerial: json['coverSerial'] as String? ?? '',
    coverPath: json['coverPath'] as String? ?? '',
  );
}
