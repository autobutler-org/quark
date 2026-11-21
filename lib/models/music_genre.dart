/// One genre in the Quark's music library, as `GET /api/v0/music/genres`
/// lists it.
class MusicGenre {
  const MusicGenre({required this.name, this.trackCount = 0});

  /// Reads one entry of the listing's `genres`.
  factory MusicGenre.fromJson(Map<String, dynamic> json) => MusicGenre(
    name: json['name']?.toString() ?? '',
    trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
  );

  /// The genre, which the tracks listing filters on.
  final String name;

  /// How many tracks carry it.
  final int trackCount;
}
