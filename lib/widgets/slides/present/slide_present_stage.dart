import 'package:flutter/material.dart';
import 'package:quark/utils/slide_present_config.dart';
import 'package:quark/widgets/slides/slide_editor_canvas.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One slide as the audience sees it (#1165): drawn by a read-only
/// [SlideCanvas], as large as its box allows at the slide's aspect ratio,
/// centered on the theme's background, which fills the bars either side.
///
/// A tap or click on the right two thirds steps forward and on the left
/// third steps back; a swipe left steps forward and a swipe right steps
/// back. A swipe counts once it has gone far enough or is let go fast
/// enough, by [SlidePresentConfig] (#2936). A new slide comes on with its
/// [transition] (#1164), played by a [SlideTransitionView], which turns it
/// into a short cross-fade under reduced motion — Android's "Remove
/// animations", the browser's `prefers-reduced-motion`, or iOS Reduce Motion.
///
/// A screen reader hears [label]; it steps with the control bar's buttons,
/// which is why the tap areas are not offered to it.
///
/// Key prefixes: none of its own; the caller passes its own `key`.
///
/// ```dart
/// SlidePresentStage(
///   slide: c.currentSlide!,
///   size: presentation.size,
///   label: c.position,
///   transition: c.transition,
///   reverse: c.movedBack,
///   onNext: c.next,
///   onPrevious: c.previous,
/// );
/// ```
class SlidePresentStage extends StatefulWidget {
  /// Shows [slide] at [size].
  const SlidePresentStage({
    required this.slide,
    required this.size,
    required this.label,
    this.transition = SlideTransitionSpec.none,
    this.reverse = false,
    this.onNext,
    this.onPrevious,
    this.imageBuilder,
    this.theme,
    super.key,
  });

  /// The presentation's theme, which the slide is drawn in; null for none.
  final SlideTheme? theme;

  /// The slide on screen.
  final Slide slide;

  /// The presentation's slide size.
  final SlideSize size;

  /// What a screen reader hears, such as "Slide 2 of 5".
  final String label;

  /// The transition [slide] comes on with when it changes.
  final SlideTransitionSpec transition;

  /// Whether the show stepped back onto [slide], which plays [transition]
  /// the other way.
  final bool reverse;

  /// Steps forward; null at the last slide.
  final VoidCallback? onNext;

  /// Steps back; null at the first slide.
  final VoidCallback? onPrevious;

  /// Draws image elements and background images.
  final SlideImageBuilder? imageBuilder;

  @override
  State<SlidePresentStage> createState() => _SlidePresentStageState();
}

/// Stateful only for where a swipe began.
class _SlidePresentStageState extends State<SlidePresentStage> {
  double _startX = 0;

  void _endSwipe(DragEndDetails details) {
    final traveled = details.globalPosition.dx - _startX;
    final fling = details.primaryVelocity ?? 0;
    final way = traveled.abs() >= SlidePresentConfig.swipeDistance
        ? traveled
        : (fling.abs() > SlidePresentConfig.swipeVelocity ? fling : 0);
    if (way > 0) widget.onPrevious?.call();
    if (way < 0) widget.onNext?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Semantics(
      container: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTapUp: (details) {
          final width = context.size?.width ?? 0;
          final step = details.localPosition.dx < width / 3
              ? widget.onPrevious
              : widget.onNext;
          step?.call();
        },
        onHorizontalDragStart: (details) => _startX = details.globalPosition.dx,
        onHorizontalDragEnd: _endSwipe,
        child: ColoredBox(
          color: tokens.background,
          child: SlideTransitionView(
            slideId: widget.slide.id,
            transition: widget.transition,
            reverse: widget.reverse,
            child: SlideCanvas.readOnly(
              slide: widget.slide,
              size: widget.size,
              theme: widget.theme,
              imageBuilder: widget.imageBuilder,
              style: SlideEditorCanvas.styleOf(context),
            ),
          ),
        ),
      ),
    );
  }
}
