import 'package:flutter/material.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One clickable column label in a sort header. The arrow shows only on the
/// column currently doing the sorting, and a screen reader hears the same
/// thing as the cell's value: "sorted ascending" or "sorted descending".
/// The cell takes keyboard focus and sorts on Enter or Space.
class FileSortHeaderCell extends StatelessWidget {
  const FileSortHeaderCell({
    required this.label,
    required this.column,
    required this.sortColumn,
    required this.sortDirection,
    required this.onToggleSort,
    this.flex = 1,
    super.key,
  });

  final String label;
  final SortColumn column;
  final SortColumn sortColumn;
  final SortDirection sortDirection;
  final ValueChanged<SortColumn> onToggleSort;
  final int flex;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = sortColumn == column;
    return Expanded(
      flex: flex,
      child: Semantics(
        button: true,
        value: !isActive
            ? null
            : sortDirection == SortDirection.asc
            ? 'sorted ascending'
            : 'sorted descending',
        child: QuarkFocusRing(
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            onTap: () => onToggleSort(column),
            borderRadius: BorderRadius.circular(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isActive
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: 4),
                  Icon(
                    sortDirection == SortDirection.asc
                        ? QuarkIcons.arrow_upward_rounded
                        : QuarkIcons.arrow_downward_rounded,
                    size: 12,
                    color: colorScheme.onSurface,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
