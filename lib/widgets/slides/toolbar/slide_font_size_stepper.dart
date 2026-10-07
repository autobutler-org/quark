import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/toolbar/slide_choice_button.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_choice.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The text size stepper: smaller, the size the selection shares, larger.
/// The size reads to a screen reader as "Font size 36", or "Font size
/// mixed" when the selection has more than one.
///
/// Key prefixes: `slide_format_font_size` on the size, and the two
/// choices' keys on the buttons.
class SlideFontSizeStepper extends StatelessWidget {
  /// A stepper reading [size] between [smaller] and [larger].
  const SlideFontSizeStepper({
    required this.size,
    required this.smaller,
    required this.larger,
    super.key,
  });

  /// The size as shown; empty when mixed.
  final String size;

  /// One size down.
  final SlideToolbarChoice smaller;

  /// One size up.
  final SlideToolbarChoice larger;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SlideChoiceButton(choice: smaller),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 36),
          child: Semantics(
            label: 'Font size ${size.isEmpty ? 'mixed' : size}',
            excludeSemantics: true,
            child: Text(
              size,
              key: const ValueKey('slide_format_font_size'),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: tokens.foreground),
            ),
          ),
        ),
        SlideChoiceButton(choice: larger),
      ],
    );
  }
}
