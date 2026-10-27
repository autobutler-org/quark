import 'package:flutter/material.dart';
import 'package:quark/models/music_genre.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Genres tab: one [GenreListTile] per genre, the untagged tracks'
/// labeled "Unknown genre".
///
/// Key prefix: [GenreListTile]'s `music_genre_<name>` on each row.
class MusicGenresList extends StatelessWidget {
  /// Creates the list.
  const MusicGenresList({
    required this.genres,
    required this.onGenreTap,
    super.key,
  });

  /// The genres, in order.
  final List<MusicGenre> genres;

  /// Called with the tapped genre's name, '' for the untagged tracks.
  final ValueChanged<String> onGenreTap;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: genres.length,
      itemBuilder: (context, i) {
        final genre = genres[i];
        return GenreListTile(
          name: genre.name.isEmpty ? 'Unknown genre' : genre.name,
          trackCount: genre.trackCount,
          onTap: (_) => onGenreTap(genre.name),
        );
      },
    );
  }
}
