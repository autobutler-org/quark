import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark/utils/playback_time.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:video_player/video_player.dart';

/// Transport controls for the audio player: scrubber, seek, play/pause, mute
/// and playback speed.
class AudioControls extends StatefulWidget {
  final VideoPlayerController controller;

  const AudioControls({super.key, required this.controller});

  @override
  State<AudioControls> createState() => _AudioControlsState();
}

class _AudioControlsState extends State<AudioControls> {
  Timer? _positionTimer;

  @override
  void initState() {
    super.initState();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    super.dispose();
  }

  Future<void> _seekBy(Duration delta) async {
    final value = widget.controller.value;
    final target = value.position + delta;
    if (target < Duration.zero) {
      await widget.controller.seekTo(Duration.zero);
    } else if (target > value.duration) {
      await widget.controller.seekTo(value.duration);
    } else {
      await widget.controller.seekTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isPlaying = value.isPlaying;
    final position = value.position;
    final duration = value.duration;
    final isMuted = value.volume == 0;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              QuarkIcons.music_note,
              size: 120,
              color: colors.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 32),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: progress.clamp(0.0, 1.0),
                onChanged: (v) {
                  final target = Duration(
                    milliseconds: (v * duration.inMilliseconds).round(),
                  );
                  widget.controller.seekTo(target);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatPlaybackTime(position),
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    formatPlaybackTime(duration),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => _seekBy(const Duration(seconds: -10)),
                  icon: const Icon(QuarkIcons.replay_10),
                  iconSize: 28,
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  onPressed: () {
                    isPlaying
                        ? widget.controller.pause()
                        : widget.controller.play();
                  },
                  icon: Icon(
                    isPlaying ? QuarkIcons.pause : QuarkIcons.play_arrow,
                  ),
                  iconSize: 40,
                  // The theme's icon color would otherwise override the
                  // filled button's own: a slate glyph on the accent (#3257).
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    foregroundColor: QuarkTokens.of(context).primaryForeground,
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: () => _seekBy(const Duration(seconds: 10)),
                  icon: const Icon(QuarkIcons.forward_10),
                  iconSize: 28,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () {
                    widget.controller.setVolume(isMuted ? 1 : 0);
                  },
                  icon: Icon(
                    isMuted ? QuarkIcons.volume_off : QuarkIcons.volume_up,
                  ),
                ),
                PopupMenuButton<double>(
                  tooltip: 'Playback speed',
                  initialValue: value.playbackSpeed,
                  onSelected: (speed) {
                    widget.controller.setPlaybackSpeed(speed);
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      '${value.playbackSpeed.toStringAsFixed(2)}x',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
