import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

/// The chip overlaid on a video in a photo grid: a play glyph and the video's
/// length, `0:42` under an hour and `1:02:03` past one.
///
/// A video whose length is unknown gets the play glyph alone, so it still
/// reads as a video rather than as a still frame.
///
/// Like [LiveBadge] its colors are fixed rather than themed: it is drawn on
/// top of a picture, not on a surface, so a scrim and white text are what keep
/// it readable whatever the frame happens to be.
///
/// Emits no `ValueKey`s; the tile it sits on carries the tap target.
///
/// ```dart
/// Stack(
///   children: [
///     thumbnail,
///     if (item.isVideo)
///       Positioned(
///         bottom: 4,
///         left: 4,
///         child: VideoBadge(duration: item.duration),
///       ),
///   ],
/// );
/// ```
class VideoBadge extends StatelessWidget {
  /// Creates the badge for a video [duration] long, or of unknown length
  /// when null.
  const VideoBadge({this.duration, super.key});

  /// How long the video runs. Null shows the play glyph alone.
  final Duration? duration;

  /// [duration] the way a player shows it: `m:ss`, or `h:mm:ss` from an hour.
  static String format(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
        : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final duration = this.duration;
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 1, 4, 1),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(QuarkIcons.play_arrow, size: 14, color: Colors.white),
          if (duration != null)
            Text(
              format(duration),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}
