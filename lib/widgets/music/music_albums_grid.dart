import 'package:flutter/material.dart';
import 'package:quark/models/music_album.dart';
import 'package:quark/widgets/music/music_album_tile.dart';
import 'package:quark/widgets/music/music_load_more_button.dart';

/// The Albums tab: a lazily built grid of [AlbumGridTile] cards, as many
/// columns as fit, ending in a [MusicLoadMoreButton] while [hasMore].
///
/// Key prefix: [AlbumGridTile]'s `music_album_<albumKey>` on each card.
class MusicAlbumsGrid extends StatelessWidget {
  /// Creates the grid.
  const MusicAlbumsGrid({
    required this.albums,
    required this.onAlbumTap,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.onLoadMore,
    super.key,
  });

  /// The albums, in order.
  final List<MusicAlbum> albums;

  /// Called with the tapped album's key.
  final ValueChanged<String> onAlbumTap;

  /// Whether more albums are left to page in.
  final bool hasMore;

  /// Whether the next page is being fetched.
  final bool isLoadingMore;

  /// Fetches the next page; required for the button to show.
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final onLoadMore = this.onLoadMore;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              // A square cover over three lines of text.
              childAspectRatio: 0.66,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemCount: albums.length,
            itemBuilder: (context, i) =>
                MusicAlbumTile(album: albums[i], onTap: onAlbumTap),
          ),
        ),
        if (hasMore && onLoadMore != null)
          SliverToBoxAdapter(
            child: MusicLoadMoreButton(
              isLoading: isLoadingMore,
              onPressed: onLoadMore,
            ),
          ),
      ],
    );
  }
}
