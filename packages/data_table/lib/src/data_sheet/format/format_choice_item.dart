import 'package:material_ui/material_ui.dart' hide Icons;
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
    // 18px glyph and an 8px gap, the same row a Quark menu uses.
    Widget slot(Widget icon) =>
        SizedBox(width: 18, height: 18, child: Center(child: icon));
    return MenuItemButton(
      key: ValueKey(choice.key),
      onPressed: choice.onSelected,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              slot(
                swatch != null
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
              ),
              const SizedBox(width: 8),
              Text(choice.label),
            ],
          ),
          if (choice.checked) slot(const Icon(QuarkIcons.check, size: 18)),
        ],
      ),
    );
  }
}
