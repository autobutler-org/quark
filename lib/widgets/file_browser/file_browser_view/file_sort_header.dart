import 'package:flutter/material.dart';
import 'package:quark/models/file_list_column.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_sort_header_cell.dart';

/// Column headers above the list view: Name, then one per entry of [columns].
/// `FileBrowserListTile` lays its cells out from the same list and the same
/// [FileListColumn] flexes, so the labels sit over their columns.
///
/// Probe keys: those of [FileSortHeaderCell], one per column shown.
class FileSortHeader extends StatelessWidget {
  const FileSortHeader({
    required this.sortColumn,
    required this.sortDirection,
    required this.onToggleSort,
    required this.showFileSizeAndMenu,
    required this.columns,
    super.key,
  });

  final SortColumn sortColumn;
  final SortDirection sortDirection;
  final ValueChanged<SortColumn> onToggleSort;
  final bool showFileSizeAndMenu;

  /// The columns after Name, in the order they are shown.
  final List<FileListColumn> columns;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.secondary,
      // No vertical padding: each cell is a 48dp tap target on its own.
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Leading icon placeholder
          const SizedBox(width: 40),
          FileSortHeaderCell(
            label: 'Name',
            column: SortColumn.name,
            sortColumn: sortColumn,
            sortDirection: sortDirection,
            onToggleSort: onToggleSort,
            flex: FileListColumn.nameFlex,
          ),
          for (final column in columns)
            FileSortHeaderCell(
              label: column.label,
              column: column.sortColumn,
              sortColumn: sortColumn,
              sortDirection: sortDirection,
              onToggleSort: onToggleSort,
              flex: FileListColumn.flex,
            ),
          // Trailing menu placeholder
          if (showFileSizeAndMenu) const SizedBox(width: 48),
        ],
      ),
    );
  }
}
