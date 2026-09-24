import 'package:flutter/material.dart';
import 'package:quark/widgets/video_viewer/video_surface_with_controls.dart';
import 'package:video_player/video_player.dart';

/// The video surface as it appears inside the page, with rounded corners.
class InlineVideoPlayer extends StatelessWidget {
  final VideoPlayerController controller;
  final VoidCallback onToggleFullscreen;

  /// Passed to [VideoSurfaceWithControls.frameKey] for Save Frame.
  final GlobalKey? frameKey;
  final bool trimMode;
  final double trimStart;
  final double trimEnd;
  final ValueChanged<double>? onTrimStartChanged;
  final ValueChanged<double>? onTrimEndChanged;

  const InlineVideoPlayer({
    super.key,
    required this.controller,
    required this.onToggleFullscreen,
    this.frameKey,
    this.trimMode = false,
    this.trimStart = 0.0,
    this.trimEnd = 1.0,
    this.onTrimStartChanged,
    this.onTrimEndChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: VideoSurfaceWithControls(
        controller: controller,
        isFullscreen: false,
        onToggleFullscreen: onToggleFullscreen,
        frameKey: frameKey,
        trimMode: trimMode,
        trimStart: trimStart,
        trimEnd: trimEnd,
        onTrimStartChanged: onTrimStartChanged,
        onTrimEndChanged: onTrimEndChanged,
      ),
    );
  }
}
