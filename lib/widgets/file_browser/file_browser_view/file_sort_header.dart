import 'package:flutter/material.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_sort_header_cell.dart';

/// Column headers above the list view. The flex values match the row layout in
/// `FileBrowserListTile` so the labels sit over their columns.
class FileSortHeader extends StatelessWidget {
  const FileSortHeader({
    required this.sortColumn,
    required this.sortDirection,
    required this.onToggleSort,
    required this.showFileSizeAndMenu,
    super.key,
  });

  final SortColumn sortColumn;
  final SortDirection sortDirection;
  final ValueChanged<SortColumn> onToggleSort;
  final bool showFileSizeAndMenu;

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
            flex: 5,
          ),
          FileSortHeaderCell(
            label: 'Device',
            column: SortColumn.device,
            sortColumn: sortColumn,
            sortDirection: sortDirection,
            onToggleSort: onToggleSort,
            flex: 2,
          ),
          if (showFileSizeAndMenu)
            FileSortHeaderCell(
              label: 'Size',
              column: SortColumn.size,
              sortColumn: sortColumn,
              sortDirection: sortDirection,
              onToggleSort: onToggleSort,
              flex: 2,
            ),
          // Trailing menu placeholder
          if (showFileSizeAndMenu) const SizedBox(width: 48),
        ],
      ),
    );
  }
}
