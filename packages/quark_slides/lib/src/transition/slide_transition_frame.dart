import 'dart:ui';

import '../model/slide_transition_direction.dart';
import '../model/slide_transition_kind.dart';
import '../model/slide_transition_spec.dart';
import 'slide_transition_layer.dart';

/// The two slides of a transition at one moment: the [outgoing] slide
/// under the [incoming] one.
///
/// Pure math, so it is tested without a widget: [ease] turns how far
/// through the transition the clock is into how far the effect has moved,
/// and [at] places both slides for it.
///
/// ```dart
/// final frame = SlideTransitionFrame.at(
///   const SlideTransitionSpec.fade(),
///   SlideTransitionFrame.ease(controller.value),
/// );
/// frame.incoming.opacity; // 0 at the start, 1 at the end
/// ```
class SlideTransitionFrame {
  /// Creates a frame.
  const SlideTransitionFrame({required this.outgoing, required this.incoming});

  /// The slide being left, drawn underneath.
  final SlideTransitionLayer outgoing;

  /// The slide arriving, drawn on top.
  final SlideTransitionLayer incoming;

  /// How far a zoom's incoming slide has grown when it starts.
  static const zoomStartScale = 0.3;

  /// The share of [duration] that has gone after [elapsed], from 0 to 1;
  /// 1 for a zero [duration].
  static double progress(Duration elapsed, Duration duration) {
    if (duration <= Duration.zero) return 1;
    return (elapsed.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0);
  }

  /// The eased position of the effect for linear progress [t], from 0 to 1:
  /// a cubic that starts and ends slowly. [t] outside 0 to 1 is clamped.
  static double ease(double t) {
    final x = t.clamp(0.0, 1.0);
    if (x < 0.5) return 4 * x * x * x;
    final f = -2 * x + 2;
    return 1 - f * f * f / 2;
  }

  /// Both slides for [transition] at eased progress [p], from 0, the old
  /// slide alone, to 1, the new slide in place.
  ///
  /// The direction is the one the slides travel: a push to the
  /// [SlideTransitionDirection.left] moves both left, the new one coming in
  /// from the right; a wipe to the left uncovers the new slide from the
  /// right edge leftward.
  static SlideTransitionFrame at(SlideTransitionSpec transition, double p) {
    final t = p.clamp(0.0, 1.0);
    final travel = switch (transition.direction) {
      SlideTransitionDirection.left => const Offset(-1, 0),
      SlideTransitionDirection.right => const Offset(1, 0),
      SlideTransitionDirection.up => const Offset(0, -1),
      SlideTransitionDirection.down => const Offset(0, 1),
    };
    return switch (transition.kind) {
      SlideTransitionKind.none => const SlideTransitionFrame(
          outgoing: SlideTransitionLayer(opacity: 0),
          incoming: SlideTransitionLayer.still,
        ),
      SlideTransitionKind.fade => SlideTransitionFrame(
          outgoing: SlideTransitionLayer.still,
          incoming: SlideTransitionLayer(opacity: t),
        ),
      SlideTransitionKind.push => SlideTransitionFrame(
          outgoing: SlideTransitionLayer(offset: travel * t),
          incoming: SlideTransitionLayer(offset: travel * (t - 1)),
        ),
      SlideTransitionKind.wipe => SlideTransitionFrame(
          outgoing: SlideTransitionLayer.still,
          incoming: SlideTransitionLayer(
            clip: switch (transition.direction) {
              SlideTransitionDirection.left => Rect.fromLTRB(1 - t, 0, 1, 1),
              SlideTransitionDirection.right => Rect.fromLTRB(0, 0, t, 1),
              SlideTransitionDirection.up => Rect.fromLTRB(0, 1 - t, 1, 1),
              SlideTransitionDirection.down => Rect.fromLTRB(0, 0, 1, t),
            },
          ),
        ),
      SlideTransitionKind.zoom => SlideTransitionFrame(
          outgoing: SlideTransitionLayer.still,
          incoming: SlideTransitionLayer(
            opacity: t,
            scale: zoomStartScale + (1 - zoomStartScale) * t,
          ),
        ),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is SlideTransitionFrame &&
      other.outgoing == outgoing &&
      other.incoming == incoming;

  @override
  int get hashCode => Object.hash(outgoing, incoming);

  @override
  String toString() => 'SlideTransitionFrame($outgoing, $incoming)';
}
