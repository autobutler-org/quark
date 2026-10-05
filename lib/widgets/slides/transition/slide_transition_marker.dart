import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark/widgets/slides/transition/slide_transition_labels.dart';

/// The small badge on a slide's thumbnail in the slide panel that says the
/// slide plays a transition (#1164). A slide with no transition shows
/// nothing. It reads "Fade transition" to a screen reader.
///
/// Key prefixes: `slide_transition_marker` on the badge.
class SlideTransitionMarker extends StatelessWidget {
  /// The badge for [transition]; empty when its kind is none.
  const SlideTransitionMarker({required this.transition, super.key});

  /// The transition the slide plays.
  final SlideTransitionSpec transition;

  @override
  Widget build(BuildContext context) {
    if (transition.kind == SlideTransitionKind.none) {
      return const SizedBox.shrink();
    }
    final tokens = QuarkTokens.of(context);
    return Semantics(
      label: SlideTransitionLabels.describe(transition),
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('slide_transition_marker'),
        padding: EdgeInsets.all(tokens.spacingXs),
        decoration: BoxDecoration(
          color: tokens.card,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
        ),
        child: Icon(
          QuarkIcons.slide_transition,
          size: 14,
          color: tokens.foreground,
        ),
      ),
    );
  }
}
