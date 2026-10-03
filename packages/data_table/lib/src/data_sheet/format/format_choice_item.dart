import 'package:flutter/material.dart' hide Icons;
import 'package:quark_icons/quark_icons.dart';

import 'format_actions.dart';

/// One [FormatChoice] as a menu item: its glyph or color swatch, its label,
/// and a check when the highlighted cell already has it. Keyed by the
/// choice's key.
class FormatChoiceItem extends StatelessWidget {
  /// The choice the item draws and runs.
  final FormatChoice choice;

  const FormatChoiceItem({super.key, required this.choice});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final swatch = choice.swatch;
    return MenuItemButton(
      key: ValueKey(choice.key),
      onPressed: choice.onSelected,
      leadingIcon: swatch != null
          ? Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: swatch.color,
                shape: BoxShape.circle,
                border: Border.all(color: cs.outline),
              ),
            )
          : Icon(choice.icon, size: 18),
      trailingIcon:
          choice.checked ? const Icon(QuarkIcons.check, size: 18) : null,
      child: Text(choice.label),
    );
  }
}
