import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/quark_menu_label.dart';
import '../theme/quark_tokens.dart';
import 'quark_bar_chip.dart';
import 'quark_bar_icon_button.dart';

/// A bar chip reading [label] that opens a menu of [options], with a check
/// beside [selected]: the one pick-one-of-these menu (#4103), used by the
/// 3D model viewer's units and print bed and the duplicates view's "Keep"
/// format.
///
/// The chip keeps its label on a phone, because the label is the current
/// choice. [active] tints it with the primary token, for a choice that narrows
/// what the page shows.
///
/// Key prefixes: [keyPrefix] on the chip, `<keyPrefix>_option_<id>` on each
/// menu row.
///
/// ```dart
/// QuarkChoiceMenu<QuarkModelUnit>(
///   keyPrefix: 'model_viewer_unit',
///   icon: QuarkIcons.straighten_outlined,
///   label: 'Units: mm',
///   tooltip: 'Units the file is in',
///   options: [
///     for (final unit in QuarkModelUnit.values)
///       (id: unit.name, label: unit.label, value: unit),
///   ],
///   selected: QuarkModelUnit.millimeters,
///   onChanged: setUnit,
/// );
/// ```
class QuarkChoiceMenu<T> extends StatelessWidget {
  /// Creates the chip over [options].
  const QuarkChoiceMenu({
    required this.keyPrefix,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.active = false,
    super.key,
  });

  /// The chip's key, and the start of each row's.
  final String keyPrefix;

  /// The chip's glyph, from `QuarkIcons`.
  final IconData icon;

  /// The chip's text, which names the current choice.
  final String label;

  /// What the choice is for, read on hover.
  final String tooltip;

  /// The menu's rows, in order: [id] goes in the row's key.
  final List<({String id, String label, T value})> options;

  /// The value checked in the menu.
  final T selected;

  /// Called with the value of the row the user picks.
  final ValueChanged<T> onChanged;

  /// Whether the chip is tinted with the primary token, as
  /// `QuarkBarChip.active` is. False by default.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return MenuAnchor(
      alignmentOffset: QuarkBarIconButton.menuAnchorOffset,
      style: const MenuStyle(minimumSize: WidgetStatePropertyAll(Size(160, 0))),
      menuChildren: [
        for (final option in options)
          MenuItemButton(
            key: ValueKey('${keyPrefix}_option_${option.id}'),
            onPressed: () => onChanged(option.value),
            child: quarkMenuLabel(
              trailing: option.value == selected
                  ? Icon(QuarkIcons.check, color: tokens.primary)
                  : null,
              label: Text(option.label),
            ),
          ),
      ],
      builder: (context, controller, _) => QuarkBarChip(
        key: ValueKey(keyPrefix),
        icon: icon,
        label: label,
        tooltip: tooltip,
        active: active,
        // The label is the current choice, so a phone keeps it too.
        keepLabel: true,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
