import 'package:flutter/material.dart' hide Icons;
import 'package:quark_icons/quark_icons.dart';

import 'format_actions.dart';
import 'format_choice_item.dart';

/// The formatting toolbar folded into one labeled "Format" button for narrow
/// screens. Its menu holds every control the full row has: bold and italic,
/// submenus for text color, fill, alignment and number format, the decimal
/// steps, and clear formatting.
///
/// Keys: the button is `format_menu`, the submenus `format_text_color`,
/// `format_fill`, `format_align` and `format_number`; every item keeps the
/// key the full row gives it.
class FormatPhoneMenu extends StatelessWidget {
  /// What the controls do.
  final DataSheetFormatActions actions;

  const FormatPhoneMenu({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    final enabled = actions.controller.selection.contextRange != null;
    SubmenuButton submenu(
      String key,
      String label,
      IconData icon,
      List<FormatChoice> choices,
    ) =>
        SubmenuButton(
          key: ValueKey(key),
          leadingIcon: Icon(icon, size: 18),
          menuChildren: [
            for (final c in choices) FormatChoiceItem(choice: c),
          ],
          child: Text(label),
        );

    return MenuAnchor(
      menuChildren: [
        FormatChoiceItem(choice: actions.bold),
        FormatChoiceItem(choice: actions.italic),
        submenu(
          'format_text_color',
          'Text color',
          QuarkIcons.format_text_color,
          actions.textColorChoices,
        ),
        submenu(
          'format_fill',
          'Fill color',
          QuarkIcons.format_fill,
          actions.fillChoices,
        ),
        submenu(
          'format_align',
          'Align',
          QuarkIcons.format_align_left,
          actions.alignChoices,
        ),
        submenu(
          'format_number',
          'Number format',
          QuarkIcons.format_number,
          actions.numberFormatChoices,
        ),
        FormatChoiceItem(choice: actions.decreaseDecimals),
        FormatChoiceItem(choice: actions.increaseDecimals),
        FormatChoiceItem(choice: actions.clear),
      ],
      builder: (context, menu, _) => Tooltip(
        message: 'Format the selected cells',
        child: TextButton.icon(
          key: const ValueKey('format_menu'),
          icon: const Icon(QuarkIcons.format_menu, size: 20),
          label: const Text('Format'),
          onPressed:
              enabled ? () => menu.isOpen ? menu.close() : menu.open() : null,
        ),
      ),
    );
  }
}
