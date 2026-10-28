import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../../layout/quark_bar_chip.dart';
import '../../../theme/quark_tokens.dart';

/// One of the choices in a `ModelViewerStats` strip (#3228): a chip reading
/// [label] that opens a menu of [options], with a check beside [selected].
///
/// Key prefixes: [keyPrefix] on the chip, `<keyPrefix>_option_<id>` on each
/// menu row.
///
/// ```dart
/// ModelViewerChoiceChip<QuarkModelUnit>(
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
class ModelViewerChoiceChip<T> extends StatelessWidget {
  /// Creates the chip over [options].
  const ModelViewerChoiceChip({
    required this.keyPrefix,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.options,
    required this.selected,
    required this.onChanged,
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

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return MenuAnchor(
      style: MenuStyle(
        minimumSize: const WidgetStatePropertyAll(Size(160, 0)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusLg),
          ),
        ),
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: tokens.spacingSm),
        ),
      ),
      menuChildren: [
        for (final option in options)
          MenuItemButton(
            key: ValueKey('${keyPrefix}_option_${option.id}'),
            trailingIcon: option.value == selected
                ? Icon(
                    QuarkIcons.check_rounded,
                    size: 16,
                    color: tokens.primary,
                  )
                : null,
            onPressed: () => onChanged(option.value),
            child: Text(option.label),
          ),
      ],
      builder: (context, controller, _) => QuarkBarChip(
        key: ValueKey(keyPrefix),
        icon: icon,
        label: label,
        tooltip: tooltip,
        // The label is the current choice, so a phone keeps it too.
        keepLabel: true,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
