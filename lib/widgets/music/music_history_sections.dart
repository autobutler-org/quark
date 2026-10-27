import 'package:flutter/material.dart';
import 'package:quark/models/music_play.dart';
import 'package:quark/widgets/music/music_cover.dart';
import 'package:quark/widgets/music/music_items.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Recently played and Most played sections at the top of Songs (#3284):
/// the user's own play history, one [TrackListTile] per song. A section with
/// nothing in it is left out, so a user who has played nothing sees only
/// their songs.
///
/// Keys: [QuarkSection]'s `section_recently_played` and
/// `section_most_played`, and [TrackListTile]'s `music_track_<path>` on each
/// row, unique within its section.
class MusicHistorySections extends StatelessWidget {
  /// Shows [recent] and [mostPlayed].
  const MusicHistorySections({
    required this.recent,
    required this.mostPlayed,
    required this.onTrackTap,
    super.key,
  });

  /// The songs played most recently, newest first.
  final List<MusicPlay> recent;

  /// The songs played most often, most first.
  final List<MusicPlay> mostPlayed;

  /// Called with the tapped song.
  final ValueChanged<MusicTrackItem> onTrackTap;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacingMd,
        vertical: tokens.spacingSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: tokens.spacingMd,
        children: [
          for (final (title, plays) in [
            ('Recently played', recent),
            ('Most played', mostPlayed),
          ])
            if (plays.isNotEmpty)
              QuarkSection(
                title: title,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final play in plays)
                      TrackListTile(
                        item: play.track.toItem(),
                        coverBuilder: MusicCover.builder(
                          play.track.relPath,
                          serial: play.track.serial,
                          hasCover: play.track.hasCover,
                        ),
                        onTap: onTrackTap,
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
