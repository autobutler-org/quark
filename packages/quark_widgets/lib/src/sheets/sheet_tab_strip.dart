import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';
import 'sheet_tab_strip/sheet_tab.dart';

/// The row of sheet tabs under a spreadsheet: a leading add button, then one
/// tab per sheet, scrolling sideways when they do not fit.
///
/// It is always shown, even for a one-sheet workbook, so the add button is
/// always there. Every tab is 160 wide, with its name cut short by an
/// ellipsis and a menu button (a ⋮, "Sheet options") pinned to its right
/// edge. Tapping an unselected tab selects it. Tapping the selected tab,
/// long-pressing any tab, or tapping any tab's menu button opens that tab's
/// menu with Rename, Duplicate, Move left, Move right, and Delete. Move left
/// is disabled on the first tab, Move right on the last, and Delete while
/// only one tab remains.
///
/// The strip never asks for a name or a confirmation itself: every callback
/// hands the parent the tab's index, and the parent shows its own
/// `QuarkNameDialog` or `ConfirmDeleteDialog` and updates [tabNames] and
/// [selectedIndex]. The one thing the strip does on its own is scroll the
/// selected tab into view when the selection or the tab count changes.
///
/// Key prefixes: `sheet_tab_add` on the add button, `sheet_tab_<index>` on
/// each tab, `sheet_tab_menu_button_<index>` on each tab's menu button, and
/// `sheet_tab_menu_<action>` on each menu entry, where the
/// action is `rename`, `duplicate`, `move_left`, `move_right`, or `delete`.
///
/// ```dart
/// SheetTabStrip(
///   tabNames: const ['Sheet 1', 'Budget'],
///   selectedIndex: 0,
///   onSelect: controller.selectSheet,
///   onAdd: controller.addSheet,
///   onRename: (index) => showRenameDialog(index),
///   onDuplicate: controller.duplicateSheet,
///   onMoveLeft: (index) => controller.moveSheet(index, index - 1),
///   onMoveRight: (index) => controller.moveSheet(index, index + 1),
///   onDelete: (index) => confirmDelete(index),
/// );
/// ```
class SheetTabStrip extends StatefulWidget {
  /// Creates the strip over [tabNames] with [selectedIndex] selected.
  const SheetTabStrip({
    required this.tabNames,
    required this.selectedIndex,
    required this.onSelect,
    required this.onAdd,
    required this.onRename,
    required this.onDuplicate,
    required this.onMoveLeft,
    required this.onMoveRight,
    required this.onDelete,
    super.key,
  });

  /// The sheet names, in tab order. Never empty.
  final List<String> tabNames;

  /// The index into [tabNames] of the sheet the editor is showing.
  final int selectedIndex;

  /// Called with a tab's index when an unselected tab is tapped.
  final ValueChanged<int> onSelect;

  /// Called when the add button is tapped. The parent picks the new name.
  final VoidCallback onAdd;

  /// Called with a tab's index when Rename is chosen from its menu.
  final ValueChanged<int> onRename;

  /// Called with a tab's index when Duplicate is chosen from its menu.
  final ValueChanged<int> onDuplicate;

  /// Called with a tab's index when Move left is chosen from its menu. Never
  /// called for the first tab.
  final ValueChanged<int> onMoveLeft;

  /// Called with a tab's index when Move right is chosen from its menu. Never
  /// called for the last tab.
  final ValueChanged<int> onMoveRight;

  /// Called with a tab's index when Delete is chosen from its menu. Never
  /// called while only one tab remains.
  final ValueChanged<int> onDelete;

  @override
  State<SheetTabStrip> createState() => _SheetTabStripState();
}

class _SheetTabStripState extends State<SheetTabStrip> {
  // Scrolling the selected tab into view is the only state here: Flutter
  // needs a handle on the tab's element to find where it is.
  final GlobalKey _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _revealSelected();
  }

  @override
  void didUpdateWidget(SheetTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex ||
        oldWidget.tabNames.length != widget.tabNames.length) {
      _revealSelected();
    }
  }

  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _selectedKey.currentContext;
      if (context != null) Scrollable.ensureVisible(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final names = widget.tabNames;
    final last = names.length - 1;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: tokens.sidebar,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('sheet_tab_add'),
            tooltip: 'Add sheet',
            icon: const Icon(QuarkIcons.add),
            color: tokens.secondaryForeground,
            onPressed: widget.onAdd,
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < names.length; i++)
                    KeyedSubtree(
                      key: i == widget.selectedIndex ? _selectedKey : null,
                      child: SheetTab(
                        index: i,
                        name: names[i],
                        isSelected: i == widget.selectedIndex,
                        onSelect: () => widget.onSelect(i),
                        onRename: () => widget.onRename(i),
                        onDuplicate: () => widget.onDuplicate(i),
                        onMoveLeft: i > 0 ? () => widget.onMoveLeft(i) : null,
                        onMoveRight: i < last
                            ? () => widget.onMoveRight(i)
                            : null,
                        onDelete: names.length > 1
                            ? () => widget.onDelete(i)
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
