import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';
import 'music_cover_art.dart';
import 'music_track_item.dart';

/// One song row with cover art, tag metadata, and playback duration.
///
/// The tile draws only the metadata in [item]. It reports a press through
/// [onTap]; the caller decides whether that opens a player, changes a queue,
/// or does nothing. A null callback leaves the row inert.
///
/// Key prefix: `music_track_<path>` on the row.
///
/// ```dart
/// TrackListTile(
///   item: track,
///   coverBuilder: (context) => CachedNetworkImage(imageUrl: coverUrl),
///   onTap: openTrack,
/// );
/// ```
class TrackListTile extends StatelessWidget {
  /// Creates a row for [item].
  const TrackListTile({
    required this.item,
    this.coverBuilder,
    this.onTap,
    super.key,
  });

  /// The track metadata to render.
  final MusicTrackItem item;

  /// Builds the track's cover. Null shows [MusicCoverArt]'s placeholder.
  final WidgetBuilder? coverBuilder;

  /// Called with [item] when the row is tapped. Null disables tapping.
  final ValueChanged<MusicTrackItem>? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final metadata = [
      item.artist,
      item.album,
    ].where((part) => part.isNotEmpty).join(' · ');
    final duration = item.duration;
    final onTap = this.onTap;

    return ListTile(
      key: ValueKey('music_track_${item.path}'),
      contentPadding: EdgeInsets.symmetric(
        horizontal: tokens.spacingMd,
        vertical: tokens.spacingXs,
      ),
      leading: SizedBox.square(
        dimension: 48,
        child: MusicCoverArt(
          semanticLabel: 'Cover for ${item.title}',
          coverBuilder: coverBuilder,
        ),
      ),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: metadata.isEmpty
          ? null
          : Text(
              metadata,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.mutedForeground),
            ),
      trailing: duration == null
          ? null
          : Text(
              _formatDuration(duration),
              style: TextStyle(color: tokens.mutedForeground),
            ),
      onTap: onTap == null ? null : () => onTap(item),
    );
  }
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}
