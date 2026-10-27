import 'package:flutter/material.dart';
import 'package:quark/models/music_album.dart';
import 'package:quark/widgets/music/music_album_tile.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Albums section at the top of an artist's page: their albums as
/// cards that wrap onto as many rows as they need. Draws nothing without
/// [albums].
class MusicArtistAlbums extends StatelessWidget {
  /// Creates the section.
  const MusicArtistAlbums({
    required this.albums,
    required this.onAlbumTap,
    super.key,
  });

  /// The artist's albums, in order.
  final List<MusicAlbum> albums;

  /// Called with the tapped album's key.
  final ValueChanged<String> onAlbumTap;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: QuarkSection(
        title: 'Albums',
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final album in albums)
              SizedBox(
                width: 160,
                child: MusicAlbumTile(album: album, onTap: onAlbumTap),
              ),
          ],
        ),
      ),
    );
  }
}
