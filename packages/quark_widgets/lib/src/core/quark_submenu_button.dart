import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

/// A row of a menu that opens a submenu of [menuChildren] on a click, a
/// tap or Enter, the same on every device.
///
/// Flutter's `SubmenuButton` opens on hover and toggles on a click, so a
/// mouse resting on the row opens the submenu and the click that follows
/// closes it again, and the row reads as dead (#2898). On a narrow window
/// the submenu opened by hover also lands over the row, so the click picks
/// whatever item is under it. Here hovering only highlights the row; a
/// click opens the submenu and never closes it. Escape, a pick in it, or a
/// click outside close it, as with any menu, and opening it closes a
/// sibling's.
///
/// Key prefixes: none of its own; the caller's key is on the whole row, so a
/// `.probe` script or a test taps the row by it.
///
/// ```dart
/// MenuAnchor(
///   menuChildren: [
///     QuarkSubmenuButton(
///       key: const ValueKey('insert_shape'),
///       leadingIcon: const Icon(QuarkIcons.shapes),
///       menuChildren: [for (final s in shapes) MenuItemButton(...)],
///       child: const Text('Shape'),
///     ),
///   ],
///   builder: ...,
/// );
/// ```
class QuarkSubmenuButton extends StatefulWidget {
  /// A row labeled [child] opening [menuChildren].
  const QuarkSubmenuButton({
    required this.menuChildren,
    required this.child,
    this.leadingIcon,
    super.key,
  });

  /// The submenu's rows, in order.
  final List<Widget> menuChildren;

  /// The row's label.
  final Widget child;

  /// The icon before the label, or none.
  final Widget? leadingIcon;

  @override
  State<QuarkSubmenuButton> createState() => _QuarkSubmenuButtonState();
}

class _QuarkSubmenuButtonState extends State<QuarkSubmenuButton> {
  final _menu = MenuController();
  final _focus = FocusNode(debugLabel: 'QuarkSubmenuButton');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Opens the submenu unless it is open: `MenuController.open` on an open
  /// menu closes it to reopen it, and the close animation wins. The row
  /// takes focus, so Escape and the arrow keys work from there.
  void _open() {
    _focus.requestFocus();
    if (!_menu.isOpen) _menu.open();
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: _menu,
    childFocusNode: _focus,
    menuChildren: widget.menuChildren,
    builder: (context, menu, _) => MergeSemantics(
      child: Semantics(
        expanded: menu.isOpen,
        child: MenuItemButton(
          focusNode: _focus,
          leadingIcon: widget.leadingIcon,
          trailingIcon: const Icon(QuarkIcons.chevron_right),
          closeOnActivate: false,
          onPressed: _open,
          child: widget.child,
        ),
      ),
    ),
  );
}
