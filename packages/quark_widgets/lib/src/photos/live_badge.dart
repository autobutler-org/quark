import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

/// The "LIVE" chip overlaid on a live photo.
///
/// It has two forms, chosen by [ready]. Left null it is the compact chip a
/// thumbnail corner wants: text only, small enough to sit over a grid tile.
/// Given a value it is the larger viewer badge, with a status dot that lights
/// up once the live video can play, because a full-screen viewer has room to
/// say whether the video is still loading.
///
/// Its colors are deliberately fixed rather than themed: it is drawn on top of
/// a photograph, not on a surface, so a scrim and white text are what keep it
/// readable over whatever the image happens to be. Theme tokens would follow
/// the app into light mode and disappear against a bright picture.
///
/// Emits no `ValueKey`s; the thumbnail or viewer it sits on carries the tap
/// target.
///
/// ```dart
/// Stack(
///   children: [
///     thumbnail,
///     if (photo.hasLiveVideo)
///       const Positioned(top: 4, left: 4, child: LiveBadge()),
///     if (isViewer)
///       Positioned(top: 12, left: 12, child: LiveBadge(ready: videoReady)),
///   ],
/// );
/// ```
class LiveBadge extends StatelessWidget {
  /// Whether the live video has loaded far enough to play.
  ///
  /// Null on a thumbnail, where nothing is loading and the badge only marks
  /// the photo as live; the compact chip is drawn instead of the viewer badge.
  /// False dims the dot and the text while the video loads, true lights them.
  final bool? ready;

  /// Creates the badge. Pass [ready] for the viewer form.
  const LiveBadge({super.key, this.ready});

  @override
  Widget build(BuildContext context) {
    final ready = this.ready;
    if (ready == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Text(
          'LIVE',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            QuarkIcons.circle,
            size: 8,
            color: ready ? Colors.yellowAccent : Colors.white38,
          ),
          const SizedBox(width: 5),
          Text(
            'LIVE',
            style: TextStyle(
              color: ready ? Colors.white : Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
