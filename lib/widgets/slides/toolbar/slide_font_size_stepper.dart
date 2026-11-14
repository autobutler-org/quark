import 'package:material_ui/material_ui.dart';
import 'package:quark/widgets/slides/toolbar/slide_choice_button.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_choice.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The text size [QuarkStepper]: smaller, the size the selection shares, larger.
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
  Widget build(BuildContext context) => QuarkStepper(
    value: size,
    semanticsLabel: 'Font size ${size.isEmpty ? 'mixed' : size}',
    valueKey: const ValueKey('slide_format_font_size'),
    decrease: SlideChoiceButton(choice: smaller),
    increase: SlideChoiceButton(choice: larger),
  );
}
