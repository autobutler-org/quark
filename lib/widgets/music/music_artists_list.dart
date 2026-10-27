import 'package:flutter/material.dart';
import 'package:quark/models/music_artist.dart';
import 'package:quark/widgets/music/music_cover.dart';
import 'package:quark/widgets/music/music_load_more_button.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Artists tab: one [ArtistListTile] per album artist, ending in a
/// [MusicLoadMoreButton] while [hasMore].
///
/// Key prefix: [ArtistListTile]'s `music_artist_<name>` on each row.
class MusicArtistsList extends StatelessWidget {
  /// Creates the list.
  const MusicArtistsList({
    required this.artists,
    required this.onArtistTap,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.onLoadMore,
    super.key,
  });

  /// The artists, in order.
  final List<MusicArtist> artists;

  /// Called with the tapped artist's name.
  final ValueChanged<String> onArtistTap;

  /// Whether more artists are left to page in.
  final bool hasMore;

  /// Whether the next page is being fetched.
  final bool isLoadingMore;

  /// Fetches the next page; required for the button to show.
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final onLoadMore = this.onLoadMore;
    final footer = hasMore && onLoadMore != null ? 1 : 0;
    return ListView.builder(
      itemCount: artists.length + footer,
      itemBuilder: (context, i) {
        if (i == artists.length) {
          return MusicLoadMoreButton(
            isLoading: isLoadingMore,
            onPressed: onLoadMore!,
          );
        }
        final artist = artists[i];
        return ArtistListTile(
          // The untagged artist's name is '': it still reaches the artist
          // page, and only its label needs words.
          name: artist.name.isEmpty ? 'Unknown artist' : artist.name,
          albumCount: artist.albumCount,
          trackCount: artist.trackCount,
          coverBuilder: MusicCover.builder(
            artist.coverPath,
            serial: artist.coverSerial,
          ),
          onTap: (_) => onArtistTap(artist.name),
        );
      },
    );
  }
}
