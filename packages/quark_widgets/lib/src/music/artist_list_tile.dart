import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';
import 'music_cover_art.dart';

/// One artist row with representative cover art and library counts.
///
/// The caller owns image loading through [coverBuilder] and receives [name]
/// from [onTap], so the widget never fetches or navigates.
///
/// Key prefix: `music_artist_<name>` on the row.
///
/// ```dart
/// ArtistListTile(
///   name: artist.name,
///   albumCount: artist.albumCount,
///   trackCount: artist.trackCount,
///   onTap: openArtist,
/// );
/// ```
class ArtistListTile extends StatelessWidget {
  /// Creates an artist row.
  const ArtistListTile({
    required this.name,
    required this.albumCount,
    required this.trackCount,
    required this.onTap,
    this.coverBuilder,
    super.key,
  });

  /// The artist's display name and stable API identity.
  final String name;

  /// The number of albums credited to the artist.
  final int albumCount;

  /// The number of tracks credited to the artist.
  final int trackCount;

  /// Builds representative cover art. Null shows the placeholder.
  final WidgetBuilder? coverBuilder;

  /// Called with [name] when the row is tapped.
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return ListTile(
      key: ValueKey('music_artist_$name'),
      contentPadding: EdgeInsets.symmetric(
        horizontal: tokens.spacingMd,
        vertical: tokens.spacingXs,
      ),
      leading: ClipOval(
        child: SizedBox.square(
          dimension: 48,
          child: MusicCoverArt(
            semanticLabel: 'Cover for $name',
            coverBuilder: coverBuilder,
          ),
        ),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '$albumCount ${albumCount == 1 ? 'album' : 'albums'} · '
        '$trackCount ${trackCount == 1 ? 'track' : 'tracks'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: tokens.mutedForeground),
      ),
      onTap: () => onTap(name),
    );
  }
}
