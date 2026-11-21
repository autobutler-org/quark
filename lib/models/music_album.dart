/// One album in the Quark's music library, as `GET /api/v0/music/albums`
/// lists it.
class MusicAlbum {
  const MusicAlbum({
    required this.key,
    required this.title,
    this.albumArtist = '',
    this.trackCount = 0,
    this.year = 0,
    this.coverPath = '',
    this.coverSerial = '',
  });

  /// Reads one entry of the listing's `albums`.
  factory MusicAlbum.fromJson(Map<String, dynamic> json) => MusicAlbum(
    key: json['albumKey']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    albumArtist: json['albumArtist']?.toString() ?? '',
    trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
    year: (json['year'] as num?)?.toInt() ?? 0,
    coverPath: json['coverPath']?.toString() ?? '',
    coverSerial: json['coverSerial']?.toString() ?? '',
  );

  /// The album's identity, which `GET /api/v0/music/tracks` filters on.
  final String key;

  /// The album's title.
  final String title;

  /// The credited album artist, empty when untagged.
  final String albumArtist;

  /// How many tracks of it the caller can read.
  final int trackCount;

  /// The earliest tagged year among its tracks, 0 when none is.
  final int year;

  /// The track to ask the thumbnail endpoint for its cover, empty for none.
  final String coverPath;

  /// The device holding [coverPath], empty for the internal drive.
  final String coverSerial;
}
