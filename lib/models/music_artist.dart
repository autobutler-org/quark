/// One album artist in the Quark's music library, as
/// `GET /api/v0/music/artists` lists it.
class MusicArtist {
  const MusicArtist({
    required this.name,
    this.albumCount = 0,
    this.trackCount = 0,
    this.coverPath = '',
    this.coverSerial = '',
  });

  /// Reads one entry of the listing's `artists`.
  factory MusicArtist.fromJson(Map<String, dynamic> json) => MusicArtist(
    name: json['name']?.toString() ?? '',
    albumCount: (json['albumCount'] as num?)?.toInt() ?? 0,
    trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
    coverPath: json['coverPath']?.toString() ?? '',
    coverSerial: json['coverSerial']?.toString() ?? '',
  );

  /// The artist's name, which the tracks and albums listings filter on.
  final String name;

  /// How many albums credit them.
  final int albumCount;

  /// How many tracks credit them.
  final int trackCount;

  /// A track of theirs to ask the thumbnail endpoint for, empty for none.
  final String coverPath;

  /// The device holding [coverPath], empty for the internal drive.
  final String coverSerial;
}
