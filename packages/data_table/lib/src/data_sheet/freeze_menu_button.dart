import 'package:flutter/material.dart' hide Icons;
import 'package:quark_icons/quark_icons.dart';

import 'cell/heading/util.dart';
import 'data_sheet_controller.dart';

/// The control bar's Freeze button: a menu that freezes none, one, or two
/// header rows or columns, or every row or column up to the selected cell.
///
/// The current choice is checked. Frozen rows and columns stay in place while
/// the rest of the grid scrolls, behind a divider.
///
/// Keys: the button is `data_sheet_freeze`; its items are `freeze_rows_0`,
/// `freeze_rows_1`, `freeze_rows_2`, `freeze_rows_selection`,
/// `freeze_columns_0`, `freeze_columns_1`, `freeze_columns_2`, and
/// `freeze_columns_selection`. The two selection items appear only while a
/// cell is selected.
///
/// ```dart
/// DataSheetFreezeMenuButton(controller: controller)
/// ```
class DataSheetFreezeMenuButton extends StatelessWidget {
  /// The sheet whose `frozenRows` and `frozenColumns` the menu sets.
  final DataSheetController controller;

  /// Creates the Freeze menu for [controller].
  const DataSheetFreezeMenuButton({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final sel = controller.selection;
    final rows = controller.frozenRows;
    final cols = controller.frozenColumns;

    CheckedPopupMenuItem<VoidCallback> item(
      String key,
      String label,
      bool checked,
      VoidCallback action,
    ) =>
        CheckedPopupMenuItem<VoidCallback>(
          key: ValueKey(key),
          value: action,
          checked: checked,
          child: Text(label),
        );

    return PopupMenuButton<VoidCallback>(
      key: const ValueKey('data_sheet_freeze'),
      tooltip: 'Freeze rows and columns',
      icon: const Icon(QuarkIcons.freeze_panes, size: 20),
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        for (final n in [0, 1, 2])
          item(
            'freeze_rows_$n',
            switch (n) { 0 => 'No rows', 1 => '1 row', _ => '$n rows' },
            rows == n,
            () => controller.setFrozenRows(n),
          ),
        if (sel.contextRow >= 0)
          item(
            'freeze_rows_selection',
            'Up to row ${sel.contextRow + 1}',
            rows == sel.contextRow + 1,
            () => controller.setFrozenRows(sel.contextRow + 1),
          ),
        const PopupMenuDivider(),
        for (final n in [0, 1, 2])
          item(
            'freeze_columns_$n',
            switch (n) {
              0 => 'No columns',
              1 => '1 column',
              _ => '$n columns',
            },
            cols == n,
            () => controller.setFrozenColumns(n),
          ),
        if (sel.contextCol >= 0)
          item(
            'freeze_columns_selection',
            'Up to column ${columnLabel(sel.contextCol)}',
            cols == sel.contextCol + 1,
            () => controller.setFrozenColumns(sel.contextCol + 1),
          ),
      ],
    );
  }
}
