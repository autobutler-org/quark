import 'package:flutter/material.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_sort_header_cell.dart';

/// Column headers above the grid view. The grid has no columns to line up
/// with, so every cell takes an equal share.
class FileGridSortHeader extends StatelessWidget {
  const FileGridSortHeader({
    required this.sortColumn,
    required this.sortDirection,
    required this.onToggleSort,
    super.key,
  });

  final SortColumn sortColumn;
  final SortDirection sortDirection;
  final ValueChanged<SortColumn> onToggleSort;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.secondary,
      // No vertical padding: each cell is a 48dp tap target on its own.
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          FileSortHeaderCell(
            label: 'Name',
            column: SortColumn.name,
            sortColumn: sortColumn,
            sortDirection: sortDirection,
            onToggleSort: onToggleSort,
          ),
          FileSortHeaderCell(
            label: 'Type',
            column: SortColumn.type,
            sortColumn: sortColumn,
            sortDirection: sortDirection,
            onToggleSort: onToggleSort,
          ),
          FileSortHeaderCell(
            label: 'Size',
            column: SortColumn.size,
            sortColumn: sortColumn,
            sortDirection: sortDirection,
            onToggleSort: onToggleSort,
          ),
          FileSortHeaderCell(
            label: 'Device',
            column: SortColumn.device,
            sortColumn: sortColumn,
            sortDirection: sortDirection,
            onToggleSort: onToggleSort,
          ),
        ],
      ),
    );
  }
}
