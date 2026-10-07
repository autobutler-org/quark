import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/find/slide_find_controller.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The find bar's options as labeled on-off chips: Match case, Whole word,
/// Regular expression, This slide only and Speaker notes. They wrap onto
/// more lines when the bar is narrow or the text is large.
///
/// Key prefixes: `slide_find_case`, `slide_find_word`, `slide_find_regex`,
/// `slide_find_this_slide` and `slide_find_notes`.
class SlideFindOptions extends StatelessWidget {
  /// Shows [controller]'s options.
  const SlideFindOptions({required this.controller, super.key});

  /// The find bar's state.
  final SlideFindController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final chips = [
      (
        'slide_find_case',
        'Match case',
        controller.caseSensitive,
        controller.toggleCaseSensitive,
      ),
      (
        'slide_find_word',
        'Whole word',
        controller.wholeWord,
        controller.toggleWholeWord,
      ),
      (
        'slide_find_regex',
        'Regular expression',
        controller.regex,
        controller.toggleRegex,
      ),
      (
        'slide_find_this_slide',
        'This slide only',
        controller.scope == SlideFindScope.currentSlide,
        controller.toggleCurrentSlide,
      ),
      (
        'slide_find_notes',
        'Speaker notes',
        controller.includeNotes,
        controller.toggleNotes,
      ),
    ];
    return Wrap(
      spacing: tokens.spacingSm,
      children: [
        for (final (key, label, selected, toggle) in chips)
          FilterChip(
            key: ValueKey(key),
            label: Text(label),
            selected: selected,
            onSelected: (_) => toggle(),
            materialTapTargetSize: MaterialTapTargetSize.padded,
          ),
      ],
    );
  }
}
