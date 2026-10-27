import 'package:flutter/material.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/widgets/music/music_cover.dart';
import 'package:quark/widgets/music/music_items.dart';
import 'package:quark/widgets/music/music_load_more_button.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A scrolling list of songs, one [TrackListTile] each, after any [header]
/// widgets and ending in a [MusicLoadMoreButton] while [hasMore].
///
/// Used by the Songs tab and by the album and artist pages, which put their
/// header (and the artist's albums) above the songs.
///
/// Key prefix: [TrackListTile]'s `music_track_<path>` on each row.
class MusicSongsList extends StatelessWidget {
  /// Creates the list.
  const MusicSongsList({
    required this.tracks,
    required this.onTrackTap,
    this.header = const [],
    this.hasMore = false,
    this.isLoadingMore = false,
    this.onLoadMore,
    this.emptyText,
    super.key,
  });

  /// The songs, in order.
  final List<MusicTrack> tracks;

  /// Called with the tapped song.
  final ValueChanged<MusicTrackItem> onTrackTap;

  /// Widgets scrolled above the songs.
  final List<Widget> header;

  /// Whether more songs are left to page in.
  final bool hasMore;

  /// Whether the next page is being fetched.
  final bool isLoadingMore;

  /// Fetches the next page; required for the button to show.
  final VoidCallback? onLoadMore;

  /// Shown in place of the songs when there are none; null shows nothing.
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final onLoadMore = this.onLoadMore;
    final emptyText = this.emptyText;
    final footer = hasMore && onLoadMore != null ? 1 : 0;
    final empty = tracks.isEmpty && emptyText != null ? 1 : 0;
    return ListView.builder(
      itemCount: header.length + empty + tracks.length + footer,
      itemBuilder: (context, i) {
        if (i < header.length) return header[i];
        i -= header.length;
        if (empty == 1 && i == 0) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(emptyText!, textAlign: TextAlign.center),
          );
        }
        if (i < tracks.length) {
          final track = tracks[i];
          return TrackListTile(
            item: track.toItem(),
            coverBuilder: MusicCover.builder(
              track.relPath,
              serial: track.serial,
              hasCover: track.hasCover,
            ),
            onTap: onTrackTap,
          );
        }
        return MusicLoadMoreButton(
          isLoading: isLoadingMore,
          onPressed: onLoadMore!,
        );
      },
    );
  }
}
