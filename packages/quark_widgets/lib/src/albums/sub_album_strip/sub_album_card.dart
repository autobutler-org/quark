import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../models/album_item.dart';
import '../../theme/quark_tokens.dart';

/// One sub-album in a `SubAlbumStrip`: a bordered card with the album's
/// glyph, name and photo count, which opens the album on a tap.
///
/// Key prefix: `sub_album_<id>` on the card.
///
/// ```dart
/// SubAlbumCard(album: album, onTap: () => open(album));
/// ```
class SubAlbumCard extends StatelessWidget {
  /// Creates a card for [album].
  const SubAlbumCard({required this.album, required this.onTap, super.key});

  /// How wide every card is, so two fit side by side on a phone.
  static const double width = 156;

  /// The album the card opens.
  final AlbumItem album;

  /// Called when the card is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QuarkTokens.of(context);
    final radius = BorderRadius.circular(tokens.radiusMd);
    return SizedBox(
      width: width,
      child: Material(
        color: tokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: tokens.border),
        ),
        child: InkWell(
          key: ValueKey('sub_album_${album.id}'),
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(tokens.spacingSm),
            child: Row(
              children: [
                Icon(
                  album.children.isEmpty
                      ? QuarkIcons.photo_album_outlined
                      : QuarkIcons.folder_outlined,
                  color: tokens.mutedForeground,
                ),
                SizedBox(width: tokens.spacingSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: tokens.cardForeground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        album.photoCountLabel,
                        maxLines: 1,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
