import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../theme/quark_tokens.dart';

/// One tab of a [SheetTabStrip]: the sheet's name, and the menu of actions
/// on it.
///
/// Tapping an unselected tab calls [onSelect]. Tapping the selected tab, or
/// long-pressing any tab, opens the menu anchored to the tab. Every tab also
/// has a menu button (a ⋮, "Sheet options") pinned to its right edge that
/// opens the same menu without selecting the tab, so keyboard and
/// screen-reader users can reach it. Every tab is 160 wide; a long name is
/// cut short with an ellipsis before the button. A menu entry whose callback is null is
/// shown disabled.
///
/// A part of `SheetTabStrip`, tested through it.
///
/// Key prefixes: `sheet_tab_<index>` on the tab, `sheet_tab_menu_button_<index>`
/// on each tab's menu button, and `sheet_tab_menu_<action>` on each menu
/// entry (`rename`, `duplicate`, `move_left`, `move_right`,
/// `delete`).
class SheetTab extends StatelessWidget {
  /// Creates the tab at [index], labeled [name].
  const SheetTab({
    required this.index,
    required this.name,
    required this.isSelected,
    required this.onSelect,
    required this.onRename,
    required this.onDuplicate,
    required this.onMoveLeft,
    required this.onMoveRight,
    required this.onDelete,
    super.key,
  });

  /// Where this tab sits in the strip. Also the source of its key.
  final int index;

  /// The sheet's name, shown on the tab.
  final String name;

  /// Whether this is the sheet the editor is showing.
  final bool isSelected;

  /// Selects this tab. Called on a tap while it is not selected.
  final VoidCallback onSelect;

  /// Renames this sheet, from the menu.
  final VoidCallback onRename;

  /// Duplicates this sheet, from the menu.
  final VoidCallback onDuplicate;

  /// Moves this sheet one place left, from the menu. Null disables the entry.
  final VoidCallback? onMoveLeft;

  /// Moves this sheet one place right, from the menu. Null disables the
  /// entry.
  final VoidCallback? onMoveRight;

  /// Deletes this sheet, from the menu. Null disables the entry.
  final VoidCallback? onDelete;

  Future<void> _openMenu(BuildContext context) async {
    final tokens = QuarkTokens.of(context);
    final tab = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final topLeft = tab.localToGlobal(Offset.zero, ancestor: overlay);
    final entries = <(String, String, VoidCallback?)>[
      ('rename', 'Rename', onRename),
      ('duplicate', 'Duplicate', onDuplicate),
      ('move_left', 'Move left', onMoveLeft),
      ('move_right', 'Move right', onMoveRight),
      ('delete', 'Delete', onDelete),
    ];

    final chosen = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        topLeft & tab.size,
        Offset.zero & overlay.size,
      ),
      items: [
        for (final (action, label, callback) in entries)
          PopupMenuItem(
            key: ValueKey('sheet_tab_menu_$action'),
            value: callback,
            enabled: callback != null,
            child: Text(
              label,
              style: action == 'delete' && callback != null
                  ? TextStyle(color: tokens.error)
                  : null,
            ),
          ),
      ],
    );
    chosen?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return InkWell(
      key: ValueKey('sheet_tab_$index'),
      onTap: isSelected ? () => _openMenu(context) : onSelect,
      onLongPress: () => _openMenu(context),
      child: Container(
        width: 160,
        padding: EdgeInsets.only(
          left: tokens.spacingMd,
          right: tokens.spacingXs,
        ),
        decoration: BoxDecoration(
          color: isSelected ? tokens.card : null,
          border: Border(
            top: BorderSide(
              color: isSelected ? tokens.primary : tokens.border,
              width: 2,
            ),
            right: BorderSide(color: tokens.border),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected
                      ? tokens.foreground
                      : tokens.mutedForeground,
                  fontWeight: isSelected ? FontWeight.w600 : null,
                ),
              ),
            ),
            IconButton(
              key: ValueKey('sheet_tab_menu_button_$index'),
              tooltip: 'Sheet options',
              icon: const Icon(QuarkIcons.more_vert),
              iconSize: 16,
              color: tokens.secondaryForeground,
              padding: EdgeInsets.zero,
              // Long-pressing the tab also opens the menu, so the button
              // keeps to its icon box and leaves the width to the label.
              style: const ButtonStyle(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              onPressed: () => _openMenu(context),
            ),
          ],
        ),
      ),
    );
  }
}
