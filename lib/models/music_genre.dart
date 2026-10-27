/// A genre in the music library and how many readable tracks carry it, as
/// `GET /api/v0/music/genres` returns it.
class MusicGenre {
  /// Creates a genre.
  const MusicGenre({required this.name, this.trackCount = 0});

  /// The genre's name, '' for untagged tracks.
  final String name;

  /// How many tracks carry it.
  final int trackCount;

  /// Reads one genre from the API's JSON.
  factory MusicGenre.fromJson(Map<String, dynamic> json) => MusicGenre(
    name: json['name'] as String? ?? '',
    trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
  );
}
