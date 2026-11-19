import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../layout/quark_bar_chip.dart';
import '../../layout/quark_bar_icon_button.dart';

/// A slideshow's controls: where it is, and exit, along the top; previous,
/// pause, next, interval, shuffle and music along the bottom.
///
/// A part of `SlideshowView`. Fades over [fade] as [visible] changes, and
/// takes no taps while hidden.
///
/// Key prefixes: `slideshow_position`, `slideshow_exit`,
/// `slideshow_previous`, `slideshow_play_pause`, `slideshow_next`,
/// `slideshow_interval`, `slideshow_shuffle` and `slideshow_music`.
class SlideshowControls extends StatelessWidget {
  /// Creates the controls.
  const SlideshowControls({
    required this.visible,
    required this.fade,
    required this.isPlaying,
    required this.intervalSeconds,
    required this.intervalChoices,
    required this.shuffle,
    required this.position,
    required this.count,
    required this.musicTitle,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onIntervalChanged,
    required this.onShuffleChanged,
    required this.onMusic,
    required this.onExit,
    super.key,
  });

  /// Whether the controls show.
  final bool visible;

  /// How long showing or hiding takes.
  final Duration fade;

  /// Whether the slideshow advances on its own.
  final bool isPlaying;

  /// Seconds each photo shows.
  final int intervalSeconds;

  /// The intervals the interval button steps through, in seconds.
  final List<int> intervalChoices;

  /// Whether the photos play in a shuffled order.
  final bool shuffle;

  /// The shown photo's place, zero-based.
  final int position;

  /// How many photos the slideshow has.
  final int count;

  /// The music playing, or null for none.
  final String? musicTitle;

  /// Pauses or resumes.
  final VoidCallback onPlayPause;

  /// Shows the previous photo.
  final VoidCallback onPrevious;

  /// Shows the next photo.
  final VoidCallback onNext;

  /// Called with the interval chosen, in seconds.
  final ValueChanged<int> onIntervalChanged;

  /// Called with whether to shuffle.
  final ValueChanged<bool> onShuffleChanged;

  /// Opens the music choice, or null to leave the button out.
  final VoidCallback? onMusic;

  /// Ends the slideshow.
  final VoidCallback onExit;

  /// The choice after [intervalSeconds], wrapping around to the first.
  int get _nextInterval {
    final at = intervalChoices.indexOf(intervalSeconds);
    return intervalChoices[(at + 1) % intervalChoices.length];
  }

  @override
  Widget build(BuildContext context) {
    final onMusic = this.onMusic;
    final musicTitle = this.musicTitle;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: fade,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        count == 0 ? '' : '${position + 1} / $count',
                        key: const ValueKey('slideshow_position'),
                        style: const TextStyle(
                          color: Colors.white,
                          shadows: [
                            Shadow(blurRadius: 4, color: Colors.black54),
                          ],
                        ),
                      ),
                    ),
                    QuarkBarIconButton(
                      key: const ValueKey('slideshow_exit'),
                      icon: QuarkIcons.close,
                      tooltip: 'Exit slideshow',
                      onPressed: onExit,
                    ),
                  ],
                ),
                const Spacer(),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    QuarkBarIconButton(
                      key: const ValueKey('slideshow_previous'),
                      icon: QuarkIcons.skip_previous,
                      tooltip: 'Previous',
                      onPressed: count > 1 ? onPrevious : null,
                    ),
                    QuarkBarIconButton(
                      key: const ValueKey('slideshow_play_pause'),
                      icon: isPlaying
                          ? QuarkIcons.pause
                          : QuarkIcons.play_arrow,
                      tooltip: isPlaying ? 'Pause' : 'Play',
                      onPressed: onPlayPause,
                    ),
                    QuarkBarIconButton(
                      key: const ValueKey('slideshow_next'),
                      icon: QuarkIcons.skip_next,
                      tooltip: 'Next',
                      onPressed: count > 1 ? onNext : null,
                    ),
                    QuarkBarChip(
                      key: const ValueKey('slideshow_interval'),
                      icon: QuarkIcons.schedule_rounded,
                      label: '${intervalSeconds}s',
                      tooltip: 'Seconds per photo',
                      keepLabel: true,
                      onPressed: () => onIntervalChanged(_nextInterval),
                    ),
                    QuarkBarIconButton(
                      key: const ValueKey('slideshow_shuffle'),
                      icon: QuarkIcons.shuffle,
                      tooltip: 'Shuffle',
                      selected: shuffle,
                      onPressed: () => onShuffleChanged(!shuffle),
                    ),
                    if (onMusic != null)
                      QuarkBarIconButton(
                        key: const ValueKey('slideshow_music'),
                        icon: QuarkIcons.music_note,
                        tooltip: musicTitle == null
                            ? 'Music'
                            : 'Music: $musicTitle',
                        selected: musicTitle != null,
                        onPressed: onMusic,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
