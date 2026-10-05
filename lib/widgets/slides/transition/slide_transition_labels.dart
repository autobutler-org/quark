import 'package:quark_slides/quark_slides.dart';

/// The words the transition picker, its marker and its screen reader labels
/// use for a transition's kind and direction (#1164).
///
/// Key prefixes: none.
class SlideTransitionLabels {
  const SlideTransitionLabels._();

  /// The name of [kind] in the picker.
  static String kind(SlideTransitionKind kind) => switch (kind) {
    SlideTransitionKind.none => 'None',
    SlideTransitionKind.fade => 'Fade',
    SlideTransitionKind.push => 'Push',
    SlideTransitionKind.wipe => 'Wipe',
    SlideTransitionKind.zoom => 'Zoom',
  };

  /// The name of [direction], the way the slides travel, in the picker.
  static String direction(SlideTransitionDirection direction) =>
      switch (direction) {
        SlideTransitionDirection.left => 'Left',
        SlideTransitionDirection.right => 'Right',
        SlideTransitionDirection.up => 'Up',
        SlideTransitionDirection.down => 'Down',
      };

  /// A duration as the picker's numeric label, such as `500 ms`.
  static String duration(int durationMs) => '$durationMs ms';

  /// What a screen reader says for [spec]: "Fade transition", or "Push
  /// transition, left" for a directional one.
  static String describe(SlideTransitionSpec spec) => spec.kind.isDirectional
      ? '${kind(spec.kind)} transition, '
            '${direction(spec.direction).toLowerCase()}'
      : '${kind(spec.kind)} transition';
}
