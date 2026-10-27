import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The top of an album's page: its cover beside its title, artist, year and
/// track count. The cover is at most 160 wide, and the text wraps beneath
/// it on a narrow screen.
class MusicAlbumHeader extends StatelessWidget {
  /// Creates the header.
  const MusicAlbumHeader({
    required this.title,
    required this.albumArtist,
    required this.trackCount,
    this.year,
    this.coverBuilder,
    super.key,
  });

  /// The album title.
  final String title;

  /// The album artist, '' when untagged.
  final String albumArtist;

  /// The release year, null when untagged.
  final int? year;

  /// How many tracks the album shows.
  final int trackCount;

  /// Builds the cover; null shows the placeholder.
  final WidgetBuilder? coverBuilder;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final year = this.year;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          SizedBox(
            width: 160,
            child: MusicCoverArt(
              semanticLabel: 'Cover for $title',
              coverBuilder: coverBuilder,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (albumArtist.isNotEmpty) Text(albumArtist),
              Text(
                [
                  if (year != null) '$year',
                  '$trackCount ${trackCount == 1 ? 'track' : 'tracks'}',
                ].join(' · '),
                style: TextStyle(color: tokens.mutedForeground),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
