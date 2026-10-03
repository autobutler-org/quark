import 'package:flutter/material.dart' hide Icons;
import 'package:quark_icons/quark_icons.dart';

import 'format_actions.dart';
import 'format_choice_button.dart';
import 'format_choice_menu_button.dart';

/// The formatting toolbar laid out in full, for screens wide enough to hold
/// it: bold, italic, text color, fill, the three alignments, number format,
/// fewer and more decimals, and clear formatting. Scrolls sideways when it
/// does not fit.
class FormatToolbarRow extends StatelessWidget {
  /// What the controls do.
  final DataSheetFormatActions actions;

  const FormatToolbarRow({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    const divider = SizedBox(
      height: 28,
      child: VerticalDivider(width: 12, thickness: 1),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          FormatChoiceButton(choice: actions.bold),
          FormatChoiceButton(choice: actions.italic),
          FormatChoiceMenuButton(
            buttonKey: 'format_text_color',
            icon: QuarkIcons.format_text_color,
            tooltip: 'Text color',
            choices: actions.textColorChoices,
          ),
          FormatChoiceMenuButton(
            buttonKey: 'format_fill',
            icon: QuarkIcons.format_fill,
            tooltip: 'Fill color',
            choices: actions.fillChoices,
          ),
          divider,
          for (final choice in actions.alignChoices)
            FormatChoiceButton(choice: choice),
          divider,
          FormatChoiceMenuButton(
            buttonKey: 'format_number',
            icon: QuarkIcons.format_number,
            tooltip: 'Number format',
            choices: actions.numberFormatChoices,
          ),
          FormatChoiceButton(choice: actions.decreaseDecimals),
          FormatChoiceButton(choice: actions.increaseDecimals),
          divider,
          FormatChoiceButton(choice: actions.clear),
        ],
      ),
    );
  }
}
