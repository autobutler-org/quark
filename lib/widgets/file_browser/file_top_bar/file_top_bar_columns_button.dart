import 'package:flutter/material.dart';
import 'package:quark/models/file_list_column.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The wide layout's column picker: a bar button that opens one checkbox per
/// optional column of the list view (#1566). The menu stays open while boxes
/// are ticked, so several columns change in one visit.
///
/// It is a button, not a labeled chip, because the wide path row has no room
/// left for another label.
///
/// Probe keys: `file_top_bar_columns` for the button, and
/// `file_top_bar_column_<name>` for each checkbox in its menu —
/// `file_top_bar_column_kind`, `file_top_bar_column_modified`,
/// `file_top_bar_column_device` and `file_top_bar_column_size`. Flutter's
/// `CheckboxMenuButton` hands its key on to the `MenuItemButton` it builds,
/// so a checkbox key matches both; they are one tap target.
class FileTopBarColumnsButton extends StatelessWidget {
  const FileTopBarColumnsButton({
    required this.columns,
    required this.onColumnToggled,
    super.key,
  });

  /// The columns currently shown, which are the boxes that start checked.
  final Set<FileListColumn> columns;

  /// Shows or hides a column. Null disables the button, for a view with no
  /// columns to choose.
  final FileListColumnToggle? onColumnToggled;

  @override
  Widget build(BuildContext context) {
    final onToggled = onColumnToggled;
    return MenuAnchor(
      menuChildren: [
        for (final column in FileListColumn.values)
          CheckboxMenuButton(
            key: ValueKey('file_top_bar_column_${column.name}'),
            value: columns.contains(column),
            closeOnActivate: false,
            onChanged: onToggled == null
                ? null
                : (visible) => onToggled(column, visible ?? false),
            child: Text(column.label),
          ),
      ],
      builder: (context, controller, _) => QuarkBarIconButton(
        key: const ValueKey('file_top_bar_columns'),
        icon: QuarkIcons.view_column_outlined,
        tooltip: 'Columns',
        onPressed: onToggled == null
            ? null
            : () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
