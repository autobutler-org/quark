import 'package:flutter/material.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark_icons/quark_icons.dart';

/// One clickable column label in a sort header. The arrow shows only on the
/// column currently doing the sorting.
///
/// The whole cell, at least 48dp tall, answers taps, and a screen reader hears
/// it as a button that is selected and says which way it sorts while it is
/// the sorting column (#2603, #2605).
///
/// Probe key: `file_sort_header_<column>`, for example `file_sort_header_name`.
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
        container: true,
        button: true,
        selected: isActive,
        value: !isActive
            ? null
            : sortDirection == SortDirection.asc
            ? 'Sorted ascending'
            : 'Sorted descending',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: ValueKey('file_sort_header_${column.name}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => onToggleSort(column),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: kMinInteractiveDimension,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isActive
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                      ),
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
      ),
    );
  }
}
