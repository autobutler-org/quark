import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/toolbar/slide_choice_menu_item.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_choice.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A slide toolbar button that opens a menu of [choices]: the shape kinds,
/// picture sources, font families, outline widths and the rest of the
/// one-of-a-set controls.
///
/// With a [label] it is a [QuarkBarChip] reading it, such as the font menu
/// showing the family in use; otherwise a [QuarkBarIconButton]. Either is
/// lit while [selected] and disabled while no choice applies.
///
/// Key prefixes: [buttonKey] on the button; each item keeps its choice's
/// key.
class SlideChoiceMenuButton extends StatelessWidget {
  /// A button keyed [buttonKey] opening [choices].
  const SlideChoiceMenuButton({
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.choices,
    this.label,
    this.selected,
    super.key,
  });

  /// The button's `ValueKey`.
  final String buttonKey;

  /// The button's glyph, from `QuarkIcons`.
  final IconData icon;

  /// What the button is for.
  final String tooltip;

  /// What the menu offers.
  final List<SlideToolbarChoice> choices;

  /// The word on the button; null for an icon button.
  final String? label;

  /// Whether the button shows as on, such as the shape menu while a shape
  /// tool is active.
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final enabled = choices.any((c) => c.onSelected != null);
    return MenuAnchor(
      menuChildren: [for (final c in choices) SlideChoiceMenuItem(choice: c)],
      builder: (context, menu, _) {
        final onPressed = enabled
            ? () => menu.isOpen ? menu.close() : menu.open()
            : null;
        final text = label;
        return text == null
            ? QuarkBarIconButton(
                key: ValueKey(buttonKey),
                icon: icon,
                tooltip: tooltip,
                selected: selected,
                onPressed: onPressed,
              )
            : QuarkBarChip(
                key: ValueKey(buttonKey),
                icon: icon,
                label: text,
                tooltip: tooltip,
                active: selected ?? false,
                keepLabel: true,
                onPressed: onPressed,
              );
      },
    );
  }
}
