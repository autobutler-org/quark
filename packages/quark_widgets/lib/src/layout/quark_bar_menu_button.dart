import 'package:material_ui/material_ui.dart';

import 'quark_bar_chip.dart';
import 'quark_bar_icon_button.dart';

/// A bar action that opens a menu: a [QuarkBarIconButton], or a
/// [QuarkBarChip] when it has a [label], that toggles a [MenuAnchor] holding
/// [menuChildren].
///
/// The menu is the shared panel the theme's `menuTheme` draws (#4099), so a
/// caller passes only the entries and the button's glyph and words. A chip's
/// menu opens at [QuarkBarIconButton.menuAnchorOffset], so it lines up with
/// the chip's painted edge rather than its touch margin.
///
/// This is not `QuarkMenuButton`, the vertical-ellipsis menu on an item row.
///
/// A false [enabled] renders the button disabled and the menu shut. [isBusy]
/// shows a spinner in an icon button and refuses taps, for a menu action
/// still running.
///
/// Key prefixes: none of its own. [buttonKey] goes on the button, which is
/// what a test or a `.probe` script taps; the entries carry their own keys.
///
/// ```dart
/// QuarkBarMenuButton(
///   buttonKey: const ValueKey('vault_export'),
///   icon: QuarkIcons.download_outlined,
///   label: 'Export',
///   menuChildren: [
///     MenuItemButton(
///       key: const ValueKey('vault_export_json'),
///       onPressed: () => export('json'),
///       child: const Text('Export as JSON'),
///     ),
///   ],
/// );
/// ```
class QuarkBarMenuButton extends StatelessWidget {
  /// Creates a bar button showing [icon] that opens [menuChildren].
  const QuarkBarMenuButton({
    required this.icon,
    required this.menuChildren,
    this.tooltip,
    this.label,
    this.buttonKey,
    this.selected,
    this.enabled = true,
    this.isBusy = false,
    this.keepLabel = false,
    super.key,
  });

  /// The button's glyph, from `QuarkIcons`.
  final IconData icon;

  /// The menu's entries: `MenuItemButton`s, `QuarkSubmenuButton`s, or any
  /// panel such as a picker.
  final List<Widget> menuChildren;

  /// What the button does, shown on hover and read by screen readers. Every
  /// icon button has one; a chip whose [label] already says it may leave it
  /// null.
  final String? tooltip;

  /// The word on a chip; null for an icon button.
  final String? label;

  /// The key on the button, for a test or a `.probe` script.
  final Key? buttonKey;

  /// Whether the button shows as on, such as a drawing tool's menu while
  /// that tool is armed; null for a plain action. A chip reads null as off.
  final bool? selected;

  /// Whether the button can open the menu. False renders it disabled.
  final bool enabled;

  /// Whether an action from the menu is still running. An icon button shows
  /// a spinner and refuses taps; a chip ignores it.
  final bool isBusy;

  /// Whether a chip keeps its [label] on a phone; see
  /// [QuarkBarChip.keepLabel].
  final bool keepLabel;

  @override
  Widget build(BuildContext context) {
    final text = label;
    return MenuAnchor(
      alignmentOffset: text == null
          ? Offset.zero
          : QuarkBarIconButton.menuAnchorOffset,
      menuChildren: menuChildren,
      builder: (context, menu, _) {
        final onPressed = enabled
            ? () => menu.isOpen ? menu.close() : menu.open()
            : null;
        return text == null
            ? QuarkBarIconButton(
                key: buttonKey,
                icon: icon,
                tooltip: tooltip,
                selected: selected,
                isBusy: isBusy,
                onPressed: onPressed,
              )
            : QuarkBarChip(
                key: buttonKey,
                icon: icon,
                label: text,
                tooltip: tooltip,
                active: selected ?? false,
                keepLabel: keepLabel,
                onPressed: onPressed,
              );
      },
    );
  }
}
