import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

/// What the image viewer shows on a video's page while swiping through the
/// Photos library (#3428): a play button and the video's name.
///
/// The viewer pages through photos as downloaded bytes; a video is never
/// downloaded whole, so its page is this card, and [onPlay] opens the video
/// player over the viewer. Its colors are the viewer's fixed white on black,
/// like the rest of the photo area.
///
/// Key: `image_viewer_video_play` on the play button.
class VideoPageCard extends StatelessWidget {
  /// The video's file name, shown under the button.
  final String name;

  /// Called when the play button is pressed.
  final VoidCallback onPlay;

  const VideoPageCard({super.key, required this.name, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const ValueKey('image_viewer_video_play'),
            tooltip: 'Play video',
            iconSize: 64,
            style: IconButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white70, width: 2),
            ),
            icon: const Icon(QuarkIcons.play_arrow),
            onPressed: onPlay,
          ),
          const SizedBox(height: 16),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
