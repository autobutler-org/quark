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
/// back. A new slide cross-fades in, and simply replaces the last one under
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
  State<SlidePresentStage> createState() => _SlidePresentStageState();
}

class _SlidePresentStageState extends State<SlidePresentStage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // iOS Reduce Motion does not reach MediaQuery, so a change to it has to
  // rebuild from here.
  @override
  void didChangeAccessibilityFeatures() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .reduceMotion;
    final canvas = KeyedSubtree(
      key: ValueKey(widget.slide.id),
      child: SlideCanvas.readOnly(
        slide: widget.slide,
        size: widget.size,
        theme: widget.theme,
        imageBuilder: widget.imageBuilder,
        style: SlideEditorCanvas.styleOf(context),
      ),
    );
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
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity <= -SlidePresentStage.swipeVelocity) {
            widget.onNext?.call();
          } else if (velocity >= SlidePresentStage.swipeVelocity) {
            widget.onPrevious?.call();
          }
        },
        child: ColoredBox(
          color: tokens.background,
          child: reduceMotion
              ? canvas
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: canvas,
                ),
        ),
      ),
    );
  }
}
