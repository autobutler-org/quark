import 'package:material_ui/material_ui.dart';
import 'package:quark/models/music_artist.dart';
import 'package:quark/widgets/music/music_cover.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A scrolling list of album artists, one [ArtistListTile] each.
///
/// Key prefix: `music_artist_<name>` on each row, from [ArtistListTile].
class MusicArtistList extends StatelessWidget {
  /// Lists [artists] in order.
  const MusicArtistList({
    required this.artists,
    required this.onTap,
    super.key,
  });

  /// The artists to list.
  final List<MusicArtist> artists;

  /// Called with the name of the artist tapped.
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => ListView.builder(
    physics: const AlwaysScrollableScrollPhysics(),
    itemCount: artists.length,
    itemBuilder: (context, i) {
      final artist = artists[i];
      return ArtistListTile(
        name: artist.name,
        albumCount: artist.albumCount,
        trackCount: artist.trackCount,
        coverBuilder: MusicCover.builder(artist.coverPath, artist.coverSerial),
        onTap: onTap,
      );
    },
  );
}
