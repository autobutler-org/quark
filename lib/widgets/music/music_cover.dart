import 'package:flutter/material.dart';
import 'package:quark/services/music_service.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A track's cover art from the thumbnail endpoint, filling the square
/// [MusicCoverArt] gives it. A cover the Quark cannot produce (it answers
/// 404 for a track without one) shows the same disc as the placeholder.
class MusicCover extends StatelessWidget {
  /// Creates the cover for the track at [path] on [serial].
  const MusicCover({required this.path, this.serial = '', super.key});

  /// The track's path within its device.
  final String path;

  /// The track's device, '' for the internal drive.
  final String serial;

  /// A [MusicCoverArt.coverBuilder] for the track at [path], or null, which
  /// shows the placeholder, when the track has no cover to ask for.
  static WidgetBuilder? builder(
    String path, {
    String serial = '',
    bool hasCover = true,
  }) => path.isEmpty || !hasCover
      ? null
      : (context) => MusicCover(path: path, serial: serial);

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Image.network(
      MusicService.coverUrl(path, serial: serial).toString(),
      fit: BoxFit.cover,
      errorBuilder: (context, _, _) => Center(
        child: Icon(QuarkIcons.disc_full, color: tokens.mutedForeground),
      ),
    );
  }
}
