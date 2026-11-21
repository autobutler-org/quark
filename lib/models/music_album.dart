/// One album in the Quark's music library, as `GET /api/v0/music/albums`
/// lists it.
class MusicAlbum {
  const MusicAlbum({
    required this.key,
    required this.title,
    this.albumArtist = '',
    this.trackCount = 0,
  });

  /// Reads one entry of the listing's `albums`.
  factory MusicAlbum.fromJson(Map<String, dynamic> json) => MusicAlbum(
    key: json['albumKey']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    albumArtist: json['albumArtist']?.toString() ?? '',
    trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
  );

  /// The album's identity, which `GET /api/v0/music/tracks` filters on.
  final String key;

  /// The album's title.
  final String title;

  /// The credited album artist, empty when untagged.
  final String albumArtist;

  /// How many tracks of it the caller can read.
  final int trackCount;
}
