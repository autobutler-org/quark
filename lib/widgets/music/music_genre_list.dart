import 'package:material_ui/material_ui.dart';
import 'package:quark/models/music_genre.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A scrolling list of genres, one [GenreListTile] each.
///
/// Key prefix: `music_genre_<name>` on each row, from [GenreListTile].
class MusicGenreList extends StatelessWidget {
  /// Lists [genres] in order.
  const MusicGenreList({required this.genres, required this.onTap, super.key});

  /// The genres to list.
  final List<MusicGenre> genres;

  /// Called with the name of the genre tapped.
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => ListView.builder(
    physics: const AlwaysScrollableScrollPhysics(),
    itemCount: genres.length,
    itemBuilder: (context, i) => GenreListTile(
      name: genres[i].name,
      trackCount: genres[i].trackCount,
      onTap: onTap,
    ),
  );
}
