import 'package:flutter/material.dart';
import 'package:quark/utils/playback_time.dart';
import 'package:quark/widgets/video_viewer/trim_bar.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:video_player/video_player.dart';

/// The control strip overlaid on the video: progress (or the trim bar),
/// transport buttons, volume, speed and the fullscreen toggle.
class PlayerControls extends StatelessWidget {
  final VideoPlayerController controller;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onInteraction;
  final bool trimMode;
  final double trimStart;
  final double trimEnd;
  final ValueChanged<double>? onTrimStartChanged;
  final ValueChanged<double>? onTrimEndChanged;

  const PlayerControls({
    super.key,
    required this.controller,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    required this.onInteraction,
    this.trimMode = false,
    this.trimStart = 0.0,
    this.trimEnd = 1.0,
    this.onTrimStartChanged,
    this.onTrimEndChanged,
  });

  Future<void> _seekBy(Duration delta) async {
    final value = controller.value;
    final duration = value.duration;
    if (duration <= Duration.zero) {
      return;
    }

    final current = value.position;
    final target = current + delta;
    if (target < Duration.zero) {
      await controller.seekTo(Duration.zero);
      return;
    }
    if (target > duration) {
      await controller.seekTo(duration);
      return;
    }
    await controller.seekTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final duration = value.duration;
        final position = value.position;
        final isMuted = value.volume == 0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xB3000000)],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (trimMode)
                TrimBar(
                  start: trimStart,
                  end: trimEnd,
                  duration: controller.value.duration,
                  onStartChanged: (v) {
                    onTrimStartChanged?.call(v);
                    final ms = (v * controller.value.duration.inMilliseconds)
                        .round();
                    controller.seekTo(Duration(milliseconds: ms));
                  },
                  onEndChanged: (v) {
                    onTrimEndChanged?.call(v);
                    final ms = (v * controller.value.duration.inMilliseconds)
                        .round();
                    controller.seekTo(Duration(milliseconds: ms));
                  },
                )
              else
                VideoProgressIndicator(
                  controller,
                  allowScrubbing: !trimMode,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  colors: VideoProgressColors(
                    playedColor: Theme.of(context).colorScheme.primary,
                    bufferedColor: Colors.white54,
                    backgroundColor: Colors.white24,
                  ),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        onInteraction();
                        value.isPlaying
                            ? controller.pause()
                            : controller.play();
                      },
                      icon: Icon(
                        value.isPlaying
                            ? QuarkIcons.pause
                            : QuarkIcons.play_arrow,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        onInteraction();
                        _seekBy(const Duration(seconds: -10));
                      },
                      icon: const Icon(
                        QuarkIcons.replay_10,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        onInteraction();
                        _seekBy(const Duration(seconds: 10));
                      },
                      icon: const Icon(
                        QuarkIcons.forward_10,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${formatPlaybackTime(position)} / ${formatPlaybackTime(duration)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    IconButton(
                      onPressed: () {
                        onInteraction();
                        controller.setVolume(isMuted ? 1 : 0);
                      },
                      icon: Icon(
                        isMuted ? QuarkIcons.volume_off : QuarkIcons.volume_up,
                        color: Colors.white,
                      ),
                    ),
                    PopupMenuButton<double>(
                      tooltip: 'Playback speed',
                      initialValue: value.playbackSpeed,
                      onSelected: (speed) {
                        onInteraction();
                        controller.setPlaybackSpeed(speed);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 0.5, child: Text('0.5x')),
                        PopupMenuItem(value: 0.75, child: Text('0.75x')),
                        PopupMenuItem(value: 1.0, child: Text('1.0x')),
                        PopupMenuItem(value: 1.25, child: Text('1.25x')),
                        PopupMenuItem(value: 1.5, child: Text('1.5x')),
                        PopupMenuItem(value: 2.0, child: Text('2.0x')),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '${value.playbackSpeed.toStringAsFixed(2)}x',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        onInteraction();
                        onToggleFullscreen();
                      },
                      icon: Icon(
                        isFullscreen
                            ? QuarkIcons.fullscreen_exit
                            : QuarkIcons.fullscreen,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
