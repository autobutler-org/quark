import 'package:material_ui/material_ui.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/widgets/music/music_cover.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// [track] as the package's music widgets draw it.
MusicTrackItem musicTrackItem(MusicTrack track) => MusicTrackItem(
  path: track.relPath,
  serial: track.serial,
  title: track.title,
  artist: track.artist,
  album: track.album,
  duration: track.durationMs > 0
      ? Duration(milliseconds: track.durationMs)
      : null,
);

/// A scrolling list of songs, one [TrackListTile] each, with [header] above
/// them. Always scrollable, so a phone can pull a short list to refresh.
///
/// Key prefix: `music_track_<path>` on each row, from [TrackListTile].
class MusicTrackList extends StatelessWidget {
  /// Lists [tracks] in order.
  const MusicTrackList({
    required this.tracks,
    required this.onTap,
    this.header,
    super.key,
  });

  /// The songs to list.
  final List<MusicTrack> tracks;

  /// Called with the song tapped.
  final ValueChanged<MusicTrack> onTap;

  /// Drawn above the first song, such as the genre filter.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final header = this.header;
    final offset = header == null ? 0 : 1;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: tracks.length + offset,
      itemBuilder: (context, i) {
        if (i < offset) return header!;
        final track = tracks[i - offset];
        return TrackListTile(
          item: musicTrackItem(track),
          coverBuilder: track.hasCover
              ? MusicCover.builder(track.relPath, track.serial)
              : null,
          onTap: (_) => onTap(track),
        );
      },
    );
  }
}
