import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/slide_editor_canvas.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One slide as the audience sees it (#1165): drawn by a read-only
/// [SlideCanvas], as large as its box allows at the slide's aspect ratio,
/// centered on the theme's background, which fills the bars either side.
///
/// A tap or click on the right two thirds steps forward and on the left
/// third steps back; a swipe left steps forward and a swipe right steps
/// back. A new slide comes on with its [transition] (#1164), played by a
/// [SlideTransitionView], which turns it into a short cross-fade under
/// reduced motion — Android's "Remove animations", the browser's
/// `prefers-reduced-motion`, or iOS Reduce Motion.
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
class SlidePresentStage extends StatelessWidget {
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

  /// How fast a horizontal fling has to be, in logical pixels a second, to
  /// count as a swipe.
  static const double swipeVelocity = 300;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Semantics(
      container: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTapUp: (details) {
          final width = context.size?.width ?? 0;
          final step = details.localPosition.dx < width / 3
              ? onPrevious
              : onNext;
          step?.call();
        },
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity <= -SlidePresentStage.swipeVelocity) {
            onNext?.call();
          } else if (velocity >= SlidePresentStage.swipeVelocity) {
            onPrevious?.call();
          }
        },
        child: ColoredBox(
          color: tokens.background,
          child: SlideTransitionView(
            slideId: slide.id,
            transition: transition,
            reverse: reverse,
            child: SlideCanvas.readOnly(
              slide: slide,
              size: size,
              theme: theme,
              imageBuilder: imageBuilder,
              style: SlideEditorCanvas.styleOf(context),
            ),
          ),
        ),
      ),
    );
  }
}
