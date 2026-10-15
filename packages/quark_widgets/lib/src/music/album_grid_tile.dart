import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';
import 'music_cover_art.dart';

/// An album grid card with cover art and its compact library metadata.
///
/// The caller supplies cover art through [coverBuilder] and handles navigation
/// through [onTap], keeping image loading and routes outside this package.
///
/// Key prefix: `music_album_<albumKey>` on the tappable card.
///
/// ```dart
/// AlbumGridTile(
///   albumKey: album.key,
///   title: album.title,
///   albumArtist: album.artist,
///   trackCount: album.trackCount,
///   onTap: openAlbum,
/// );
/// ```
class AlbumGridTile extends StatelessWidget {
  /// Creates an album card identified by [albumKey].
  const AlbumGridTile({
    required this.albumKey,
    required this.title,
    required this.albumArtist,
    required this.trackCount,
    required this.onTap,
    this.year,
    this.coverBuilder,
    super.key,
  });

  /// The API's stable identity for the album.
  final String albumKey;

  /// The album title.
  final String title;

  /// The credited album artist.
  final String albumArtist;

  /// The release year, or null when the tags do not contain one.
  final int? year;

  /// The number of tracks grouped into the album.
  final int trackCount;

  /// Builds the album's cover. Null shows [MusicCoverArt]'s placeholder.
  final WidgetBuilder? coverBuilder;

  /// Called with [albumKey] when the card is tapped.
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final year = this.year;
    final byline = [
      albumArtist,
      if (year != null) '$year',
    ].where((part) => part.isNotEmpty).join(' · ');
    final radius = BorderRadius.circular(tokens.radiusLg);

    return DecoratedBox(
      key: ValueKey('music_album_surface_$albumKey'),
      decoration: BoxDecoration(
        color: tokens.card,
        border: Border.all(color: tokens.border),
        borderRadius: radius,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        child: InkWell(
          key: ValueKey('music_album_$albumKey'),
          borderRadius: radius,
          onTap: () => onTap(albumKey),
          child: Padding(
            padding: EdgeInsets.all(tokens.spacingSm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MusicCoverArt(
                  semanticLabel: 'Cover for $title',
                  coverBuilder: coverBuilder,
                ),
                SizedBox(height: tokens.spacingSm),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (byline.isNotEmpty) ...[
                  SizedBox(height: tokens.spacingXs),
                  Text(
                    byline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tokens.mutedForeground),
                  ),
                ],
                SizedBox(height: tokens.spacingXs),
                Text(
                  '$trackCount ${trackCount == 1 ? 'track' : 'tracks'}',
                  style: TextStyle(color: tokens.mutedForeground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
