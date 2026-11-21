import 'package:material_ui/material_ui.dart';
import 'package:quark/models/music_album.dart';
import 'package:quark/widgets/music/music_cover.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A scrolling grid of albums, one [AlbumGridTile] each, as many across as
/// fit at about 200 px a column.
///
/// Key prefix: `music_album_<albumKey>` on each card, from [AlbumGridTile].
class MusicAlbumGrid extends StatelessWidget {
  /// Shows [albums] in order.
  const MusicAlbumGrid({required this.albums, required this.onTap, super.key});

  /// The albums to show.
  final List<MusicAlbum> albums;

  /// Called with the key of the album tapped.
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(tokens.spacingMd),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        // Tall enough for the square cover and three lines of text below it
        // at the narrowest column.
        childAspectRatio: 0.6,
        mainAxisSpacing: tokens.spacingMd,
        crossAxisSpacing: tokens.spacingMd,
      ),
      itemCount: albums.length,
      itemBuilder: (context, i) {
        final album = albums[i];
        return AlbumGridTile(
          albumKey: album.key,
          title: album.title,
          albumArtist: album.albumArtist,
          year: album.year > 0 ? album.year : null,
          trackCount: album.trackCount,
          coverBuilder: MusicCover.builder(album.coverPath, album.coverSerial),
          onTap: onTap,
        );
      },
    );
  }
}
