import 'package:flutter/material.dart';

import '../models/album_item.dart';
import '../theme/quark_tokens.dart';
import 'sub_album_strip/sub_album_card.dart';

/// The sub-albums of the album a page shows, as a sliver of cards to sit
/// above that album's photo grid (#2591).
///
/// Without it a nested album shows only as a row in the sidebar tree, so the
/// album's own view gives no sign that it holds another. Pass the showing
/// album's direct children as [albums], in the order the sidebar lists them;
/// each card opens through [onSelected]. With no sub-albums the sliver takes
/// no space at all.
///
/// A sliver so it can share a scroll view with the grid under it: put it in
/// `QuarkSplitView.slivers` ahead of `PhotoGrid`.
///
/// Key prefixes: `sub_album_strip` on the strip, and `sub_album_<id>` on each
/// card.
///
/// ```dart
/// SubAlbumStrip(
///   albums: controller.subAlbums,
///   onSelected: (album) => showAlbum(album.id),
/// );
/// ```
class SubAlbumStrip extends StatelessWidget {
  /// Creates a strip of [albums].
  const SubAlbumStrip({
    required this.albums,
    required this.onSelected,
    super.key,
  });

  /// The showing album's sub-albums, in display order.
  final List<AlbumItem> albums;

  /// Called with the sub-album whose card was tapped.
  final ValueChanged<AlbumItem> onSelected;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) return const SliverToBoxAdapter();
    final theme = Theme.of(context);
    final tokens = QuarkTokens.of(context);
    return SliverToBoxAdapter(
      key: const ValueKey('sub_album_strip'),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tokens.spacingMd,
          tokens.spacingMd,
          tokens.spacingMd,
          tokens.spacingSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Albums',
              style: theme.textTheme.titleSmall?.copyWith(
                color: tokens.secondaryForeground,
              ),
            ),
            SizedBox(height: tokens.spacingSm),
            Wrap(
              spacing: tokens.spacingSm,
              runSpacing: tokens.spacingSm,
              children: [
                for (final album in albums)
                  SubAlbumCard(album: album, onTap: () => onSelected(album)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
