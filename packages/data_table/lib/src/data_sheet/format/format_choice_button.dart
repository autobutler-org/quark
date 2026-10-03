import 'package:flutter/material.dart' hide Icons;

import 'format_actions.dart';

/// One [FormatChoice] as a toolbar button: its glyph with its label as the
/// tooltip, drawn in the theme's primary color while the highlighted cell
/// has it. Keyed by the choice's key.
class FormatChoiceButton extends StatelessWidget {
  /// The choice the button draws and runs.
  final FormatChoice choice;

  const FormatChoiceButton({super.key, required this.choice});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: choice.label,
      child: IconButton(
        key: ValueKey(choice.key),
        icon: Icon(choice.icon),
        isSelected: choice.checked,
        color: choice.checked ? Theme.of(context).colorScheme.primary : null,
        onPressed: choice.onSelected,
        iconSize: 20,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
