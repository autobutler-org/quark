import 'package:material_ui/material_ui.dart';

import '../theme/reduce_motion.dart';
import 'slideshow_view/slideshow_controls.dart';
import 'slideshow_view/slideshow_stage.dart';

/// A full-screen photo slideshow: each photo whole on black, cross-fading
/// into the next, with controls over it that come and go.
///
/// It holds no slideshow state of its own. The caller passes the photo to
/// show as [image], whether it is [isPlaying], the [intervalSeconds] and the
/// [shuffle] flag, and whether the controls are [controlsVisible], and is told
/// about every action through a callback. A tap anywhere or a mouse move
/// calls [onActivity], which is how the caller knows to show the controls
/// and hide them again later.
///
/// Under reduced motion, from `reduceMotionOf` (Android's "Remove
/// animations", the browser's `prefers-reduced-motion`, or iOS Reduce
/// Motion), the photos change at once, with no cross-fade, and the controls
/// appear and disappear without fading.
///
/// [onMusic] null leaves the music button out, for a Quark with no music.
///
/// Key prefixes: `slideshow_view` on the whole view, `slideshow_slide_<id>`
/// on the photo shown, `slideshow_error` on an error, and on the controls
/// `slideshow_position`, `slideshow_exit`, `slideshow_previous`,
/// `slideshow_play_pause`, `slideshow_next`, `slideshow_interval`,
/// `slideshow_shuffle` and `slideshow_music`.
///
/// ```dart
/// SlideshowView(
///   image: MemoryImage(bytes),
///   slideId: photo.id,
///   isPlaying: controller.isPlaying,
///   intervalSeconds: controller.intervalSeconds,
///   shuffle: controller.shuffle,
///   position: controller.position,
///   count: controller.count,
///   controlsVisible: controller.controlsVisible,
///   onActivity: controller.showControls,
///   onPlayPause: controller.togglePlaying,
///   onPrevious: controller.previous,
///   onNext: controller.next,
///   onIntervalChanged: controller.setInterval,
///   onShuffleChanged: controller.setShuffle,
///   onExit: () => Navigator.of(context).pop(),
/// );
/// ```
class SlideshowView extends StatefulWidget {
  /// Creates the view showing [image].
  const SlideshowView({
    required this.image,
    required this.slideId,
    required this.isPlaying,
    required this.intervalSeconds,
    required this.shuffle,
    required this.position,
    required this.count,
    required this.controlsVisible,
    required this.onActivity,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onIntervalChanged,
    required this.onShuffleChanged,
    required this.onExit,
    this.intervalChoices = defaultIntervalChoices,
    this.isLoading = false,
    this.error,
    this.musicTitle,
    this.onMusic,
    super.key,
  });

  /// The intervals offered unless the caller passes its own: 3, 5, 10 and 15
  /// seconds.
  static const List<int> defaultIntervalChoices = [3, 5, 10, 15];

  /// How long one photo takes to fade into the next, with motion allowed.
  static const Duration crossFade = Duration(milliseconds: 600);

  /// The photo to show, or null before the first has loaded.
  final ImageProvider? image;

  /// The shown photo's identity: a new one cross-fades in.
  final String? slideId;

  /// Whether the first photo is still loading.
  final bool isLoading;

  /// Why the photo could not be shown, written by the caller, or null.
  final String? error;

  /// Whether the slideshow advances on its own; the pause button shows play
  /// when it does not.
  final bool isPlaying;

  /// Seconds each photo shows, one of [intervalChoices].
  final int intervalSeconds;

  /// The intervals the interval button steps through, in seconds.
  final List<int> intervalChoices;

  /// Whether the photos play shuffled.
  final bool shuffle;

  /// The shown photo's place in the slideshow, zero-based.
  final int position;

  /// How many photos the slideshow has.
  final int count;

  /// Whether the controls show.
  final bool controlsVisible;

  /// The music playing, or null for none.
  final String? musicTitle;

  /// Called on a tap anywhere or a mouse move over the view.
  final VoidCallback onActivity;

  /// Pauses or resumes.
  final VoidCallback onPlayPause;

  /// Shows the previous photo.
  final VoidCallback onPrevious;

  /// Shows the next photo.
  final VoidCallback onNext;

  /// Called with the interval the user stepped to, in seconds.
  final ValueChanged<int> onIntervalChanged;

  /// Called with whether to shuffle.
  final ValueChanged<bool> onShuffleChanged;

  /// Opens the music choice; null leaves the button out.
  final VoidCallback? onMusic;

  /// Ends the slideshow.
  final VoidCallback onExit;

  @override
  State<SlideshowView> createState() => _SlideshowViewState();
}

class _SlideshowViewState extends State<SlideshowView>
    with WidgetsBindingObserver {
  static const _controlsFade = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  // iOS Reduce Motion does not reach MediaQuery, so a change to it has to
  // rebuild the view by hand.
  @override
  void didChangeAccessibilityFeatures() => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotionOf(context);
    return ColoredBox(
      key: const ValueKey('slideshow_view'),
      // Photos show on black, whatever the theme.
      color: Colors.black,
      child: MouseRegion(
        onHover: (_) => widget.onActivity(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onActivity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SlideshowStage(
                image: widget.image,
                slideId: widget.slideId,
                isLoading: widget.isLoading,
                error: widget.error,
                fade: reduce ? Duration.zero : SlideshowView.crossFade,
              ),
              SlideshowControls(
                visible: widget.controlsVisible,
                fade: reduce ? Duration.zero : _controlsFade,
                isPlaying: widget.isPlaying,
                intervalSeconds: widget.intervalSeconds,
                intervalChoices: widget.intervalChoices,
                shuffle: widget.shuffle,
                position: widget.position,
                count: widget.count,
                musicTitle: widget.musicTitle,
                onPlayPause: widget.onPlayPause,
                onPrevious: widget.onPrevious,
                onNext: widget.onNext,
                onIntervalChanged: widget.onIntervalChanged,
                onShuffleChanged: widget.onShuffleChanged,
                onMusic: widget.onMusic,
                onExit: widget.onExit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
