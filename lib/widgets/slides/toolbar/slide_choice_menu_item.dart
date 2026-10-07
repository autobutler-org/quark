import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_choice.dart';
import 'package:quark_icons/quark_icons.dart';

/// A slide toolbar choice as a menu row: its glyph, its label, and a check
/// while it is on, which a screen reader hears as selected.
///
/// Key prefixes: the choice's own `key`.
class SlideChoiceMenuItem extends StatelessWidget {
  /// Draws [choice].
  const SlideChoiceMenuItem({required this.choice, super.key});

  /// The control.
  final SlideToolbarChoice choice;

  @override
  Widget build(BuildContext context) {
    final on = choice.selected ?? false;
    return Semantics(
      selected: choice.selected,
      child: MenuItemButton(
        key: ValueKey(choice.key),
        leadingIcon: choice.icon == null ? null : Icon(choice.icon),
        trailingIcon: on ? const Icon(QuarkIcons.check) : null,
        onPressed: choice.onSelected,
        child: Text(choice.label),
      ),
    );
  }
}
