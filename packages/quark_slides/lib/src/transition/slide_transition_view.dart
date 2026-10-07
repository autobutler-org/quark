import 'package:flutter/widgets.dart';

import '../model/slide_transition_kind.dart';
import '../model/slide_transition_spec.dart';
import 'slide_transition_clipper.dart';
import 'slide_transition_frame.dart';
import 'slide_transition_layer.dart';

/// Shows [child], the slide with [slideId], and plays [transition] from the
/// slide it showed before whenever [slideId] changes.
///
/// During the transition the old slide's last [child] stays on screen under
/// the new one, both placed by `SlideTransitionFrame.at` and clipped to the
/// box, so a push never draws outside it. The first slide it shows simply
/// appears, and a [SlideTransitionKind.none] transition is an instant cut.
/// A change of slide in mid-transition starts the next one from the slide
/// that was arriving.
///
/// [reverse] plays the transition stepping back: a push or wipe moves the
/// other way, so going back undoes the motion that came forward.
///
/// Reduced motion — Android's "Remove animations" and the browser's
/// `prefers-reduced-motion` through `MediaQuery.disableAnimationsOf`, and
/// iOS Reduce Motion through the platform's accessibility features, which
/// do not reach `MediaQuery` — turns every transition into
/// [SlideTransitionSpec.reducedMotion], a short cross-fade with no
/// movement, so the change still reads. Turning it on mid-transition
/// finishes the transition at once.
///
/// It is meant for read-only slides, such as `SlideCanvas.readOnly` when
/// presenting; it takes no input of its own, so a gesture detector around
/// it keeps working throughout.
///
/// Key prefixes: `slide_transition_<slideId>` on each slide's layer, so a
/// test or `.probe` script can tell the arriving slide from the leaving
/// one.
///
/// ```dart
/// SlideTransitionView(
///   slideId: slide.id,
///   transition: deck.transitionFor(slide),
///   reverse: wentBack,
///   child: SlideCanvas.readOnly(slide: slide, size: deck.size),
/// );
/// ```
class SlideTransitionView extends StatefulWidget {
  /// Shows [child] as the slide [slideId].
  const SlideTransitionView({
    required this.slideId,
    required this.child,
    this.transition = SlideTransitionSpec.none,
    this.reverse = false,
    super.key,
  });

  /// The id of the slide [child] draws; a change plays [transition].
  final String slideId;

  /// The transition into [slideId]; read when [slideId] changes.
  final SlideTransitionSpec transition;

  /// Whether the show stepped back onto [slideId], which plays
  /// [transition] in the reversed direction.
  final bool reverse;

  /// The slide [slideId], drawn.
  final Widget child;

  @override
  State<SlideTransitionView> createState() => _SlideTransitionViewState();
}

class _SlideTransitionViewState extends State<SlideTransitionView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // Reduced motion is applied here, as reducedMotion, so the platform's
  // "Remove animations" must not also shrink the fade it leaves to nothing.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  )..addStatusListener(_onStatus);

  /// The slide being left and how it was drawn; null when none is.
  String? _outgoingId;
  Widget? _outgoing;
  SlideTransitionSpec _playing = SlideTransitionSpec.none;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  bool get _reduceMotion =>
      MediaQuery.disableAnimationsOf(context) ||
      WidgetsBinding
          .instance.platformDispatcher.accessibilityFeatures.reduceMotion;

  // iOS Reduce Motion does not reach MediaQuery, so its change is heard
  // here; a transition already playing finishes at once.
  @override
  void didChangeAccessibilityFeatures() {
    if (_reduceMotion && _controller.isAnimating) _controller.value = 1;
    setState(() {});
  }

  @override
  void didUpdateWidget(SlideTransitionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slideId == widget.slideId) return;
    var transition =
        widget.reverse ? widget.transition.reversed : widget.transition;
    if (_reduceMotion) transition = transition.reducedMotion;
    if (transition.kind == SlideTransitionKind.none) {
      _controller.value = 1;
      _outgoing = _outgoingId = null;
      return;
    }
    _outgoingId = oldWidget.slideId;
    _outgoing = oldWidget.child;
    _playing = transition;
    _controller
      ..duration = transition.duration
      ..forward(from: 0);
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _outgoing == null) return;
    setState(() => _outgoing = _outgoingId = null);
  }

  @override
  Widget build(BuildContext context) => ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final frame = _outgoing == null
                ? const SlideTransitionFrame(
                    outgoing: SlideTransitionLayer.still,
                    incoming: SlideTransitionLayer.still,
                  )
                : SlideTransitionFrame.at(
                    _playing,
                    SlideTransitionFrame.ease(_controller.value),
                  );
            // Each layer is keyed by its slide, so the slide that was
            // arriving keeps its state as it becomes the one leaving.
            Widget layer(String id, SlideTransitionLayer at, Widget child) =>
                FractionalTranslation(
                  key: ValueKey('slide_transition_$id'),
                  translation: at.offset,
                  child: Transform.scale(
                    scale: at.scale,
                    child: Opacity(
                      opacity: at.opacity,
                      child: ClipRect(
                        clipper: SlideTransitionClipper(at.clip),
                        child: child,
                      ),
                    ),
                  ),
                );
            return Stack(
              fit: StackFit.passthrough,
              children: [
                if (_outgoing != null)
                  layer(_outgoingId!, frame.outgoing, _outgoing!),
                layer(widget.slideId, frame.incoming, widget.child),
              ],
            );
          },
        ),
      );
}
