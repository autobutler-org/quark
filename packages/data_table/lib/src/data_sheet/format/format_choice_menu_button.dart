import 'package:flutter/material.dart' hide Icons;

import 'format_actions.dart';
import 'format_choice_item.dart';

/// A toolbar button that opens a menu of [FormatChoice]s: the text color,
/// fill and number format pickers. Disabled while nothing is selected.
class FormatChoiceMenuButton extends StatelessWidget {
  /// The button's `ValueKey`.
  final String buttonKey;

  /// The button's glyph.
  final IconData icon;

  /// The button's tooltip.
  final String tooltip;

  /// What the menu offers.
  final List<FormatChoice> choices;

  const FormatChoiceMenuButton({
    super.key,
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.choices,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = choices.any((c) => c.onSelected != null);
    return MenuAnchor(
      menuChildren: [for (final c in choices) FormatChoiceItem(choice: c)],
      builder: (context, menu, _) => Tooltip(
        message: tooltip,
        child: IconButton(
          key: ValueKey(buttonKey),
          icon: Icon(icon),
          onPressed:
              enabled ? () => menu.isOpen ? menu.close() : menu.open() : null,
          iconSize: 20,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
